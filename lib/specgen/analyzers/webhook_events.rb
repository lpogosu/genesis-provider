# frozen_string_literal: true

module SpecGen
  module Analyzers
    # События одного вебхука и внутренний статус каждого.
    #
    # Роли `event` в IR::Roles::FIELD нет, и добавлять её молча нельзя,
    # поэтому поле события ищется структурно: строковое поле с enum, чьи
    # значения после снятия префикса читаются как статусы (`payout.completed`
    # -> `completed`), не являющееся при этом самим полем статуса. Кандидат
    # берётся, если так читается не меньше половины его значений; при равной
    # доле побеждает первый по схеме. Имя вроде `event` здесь ничего не
    # решает: слово, не подтверждённое значениями, — не сигнал.
    #
    # Если поля события нет, событиями становятся значения поля статуса:
    # вебхук, несущий только `status`, всё равно сообщает исход. Событие из
    # примера, которого нет в enum, добавляется с предупреждением, как и
    # статус из примера у StatusAnalyzer.
    class WebhookEvents
      # События, имя и JSONPath поля события (nil, если его нет) и заметки
      # [код, сообщение, JSONPath].
      Result = Struct.new(:events, :field, :field_path, :notes, keyword_init: true)

      STATUS = :status
      STRING = 'string'
      # Доля значений enum, читающихся как статусы, с которой поле считается
      # полем события.
      MIN_RESOLVED = 0.5

      # @param node [Hash] схема тела вебхука, `allOf` свёрнут
      # @param schema_path [String] JSONPath этой схемы
      # @param examples [Array<Array(String, Object, String)>] имя, значение
      #   и JSONPath каждого примера тела
      # @param lookup [RoleLookup]
      # @param book [Rules::StatusesBook]
      def initialize(node:, schema_path:, examples:, lookup:, book:)
        @node = node
        @schema_path = schema_path
        @examples = examples
        @lookup = lookup
        @book = book
        @notes = []
      end

      # @return [Result]
      def call
        field, enum, prefix = pick_field
        return Result.new(events: [], field: nil, notes: [no_events_note]) if field.nil?

        path = path_of(field)
        reader = StatusReader.new(book: @book, overrides: property(field)[StatusReader::EXTENSION])
        events = enum.each_with_index.map do |value, index|
          event(value, field, reader, "#{path}.enum[#{index}]", prefix)
        end
        events.concat(from_examples(field, enum, reader, prefix))
        Result.new(events: events, field: field, field_path: path, notes: @notes)
      end

      private

      # @return [String] JSONPath поля, для заготовок overlay
      def path_of(field)
        "#{@schema_path}.properties#{SpecLoader::JsonPath.segment(field)}"
      end

      # @return [Array(String, Array<String>, String), Array(nil)] имя поля,
      #   его enum и префикс обоснования
      def pick_field
        best = candidates.max_by { |_, _, ratio| ratio }
        return [best[0], best[1], ''] if best && best[2] >= MIN_RESOLVED

        status = enum_fields.find { |name, _| @lookup.role?(name, STATUS) }
        return [nil] if status.nil?

        [status[0], status[1], t('from_status_field', name: status[0])]
      end

      # @return [Array<Array(String, Array<String>, Float)>] в порядке схемы
      def candidates
        enum_fields.filter_map do |name, enum|
          next if @lookup.role?(name, STATUS)

          reader = StatusReader.new(book: @book)
          resolved = enum.count { |value| reader.call(value).kind != :unknown }
          [name, enum, resolved.to_f / enum.size]
        end
      end

      # @return [Array<Array(String, Array<String>)>] строковые поля с enum
      def enum_fields
        properties = @node['properties']
        return [] unless properties.is_a?(Hash)

        properties.filter_map do |name, body|
          next unless body.is_a?(Hash)

          merged, = SchemaFlattener.call(body)
          type, = ConstraintReader.type_of(merged)
          values = merged['enum']
          next unless (type.nil? || type == STRING) && values.is_a?(Array) && !values.empty?

          [name.to_s, values.grep(String)]
        end
      end

      def property(name)
        merged, = SchemaFlattener.call(@node['properties'][name])
        merged
      end

      def event(value, field, reader, at, prefix)
        result = reader.call(value)
        internal = prefixed(result.derived, prefix)
        IR::WebhookEvent.new(name: value, internal_status: internal,
                             provider_status: result.kind == :unknown ? nil : result.status,
                             example: example_for(field, value), json_path: at)
      end

      # Derived заморожен, поэтому обоснование с префиксом — новый Derived.
      def prefixed(derived, prefix)
        return derived if prefix.empty?

        IR::Derived.new(value: derived.value, source: derived.source,
                        confidence: derived.confidence, evidence: prefix + derived.evidence.to_s)
      end

      def example_for(field, value)
        found = @examples.find { |_, body, _| body.is_a?(Hash) && body[field] == value }
        found&.fetch(1)
      end

      # Событие из примера, которого нет в enum, — расхождение спецификации с
      # самой собой; событие всё равно добавляется, потому что оно придёт.
      def from_examples(field, enum, reader, prefix)
        @examples.filter_map do |name, body, path|
          value = body.is_a?(Hash) ? body[field] : nil
          next unless value.is_a?(String) && !enum.include?(value)

          enum << value
          @notes << [:webhook_event_undeclared,
                     t('event_undeclared', event: value, name: name, field: field), path]
          event(value, field, reader, path + SpecLoader::JsonPath.segment(field), prefix)
        end
      end

      def no_events_note
        [:webhook_event_unmapped, t('no_events', schema: @schema_path), @schema_path]
      end

      def t(key, **params)
        Texts.t("analyzers.webhook.#{key}", **params)
      end
    end
  end
end
