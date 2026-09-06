# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.status_map: каждый статус, который провайдер может
    # вернуть, и внутренний статус, в который его переводит сгенерированный
    # сервис.
    #
    # Статусы берутся из enum полей, чьё имя — точный синоним роли status
    # (RoleLookup), в порядке спецификации, и из значений таких полей в
    # примерах запросов и ответов. Одна запись на уникальный статус:
    # PayoutResponse и WebhookPayload объявляют один и тот же enum, и второй
    # раз он не записывается. Статус, встретившийся в примере, но не в enum,
    # всё равно попадает в карту — он придёт в ответе, — но с предупреждением
    # status_missing_from_enum: спецификация противоречит сама себе.
    #
    # Перевод делает StatusReader — та же логика, которой WebhookAnalyzer
    # читает события. Невыведенный статус — это предупреждение
    # status_unmapped с готовым фрагментом overlay: молча подставить
    # in_progress значило бы держать выплаченные деньги в опросе, а
    # молча подставить approved — пометить невыплаченные как выплаченные.
    class StatusAnalyzer < Base
      ROLE = :status
      EXTENSION = StatusReader::EXTENSION
      # Вид результата StatusReader -> ключ сообщения предупреждения.
      MESSAGES = { ambiguous: 'ambiguous_message', partial: 'partial_message',
                   not_status: 'not_status_message' }.freeze

      # Заполняет `profile.status_map`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @lookup = RoleLookup.new(rules, data)
        @fields = status_fields
        @fields.each { |field| from_enum(field) }
        from_examples
        no_field if @fields.empty? && profile.status_map.empty?
        profile
      end

      private

      # @return [Array<Array(SchemaIndex::Entry, String, Hash, String)>]
      def status_fields
        SchemaIndex.new(data).each_field.select { |_, name, _, _| @lookup.role?(name, ROLE) }
      end

      def from_enum(field)
        _, name, node, path = field
        enum = node['enum']
        return if enum.nil?
        return enum_shape(path) unless enum.is_a?(Array)

        reader = StatusReader.new(book: rules.statuses, overrides: node[EXTENSION])
        enum.each_with_index do |value, index|
          add(value, reader, "#{path}.enum[#{index}]", path, name) if value.is_a?(String)
        end
      end

      def enum_shape(path)
        message = Texts.t('analyzers.common.must_be_list', key: 'enum')
        profile.warn(:spec_element_unsupported, message, json_path: "#{path}.enum")
      end

      # Пример может назвать статус, которого нет ни в одном enum.
      def from_examples
        reader = StatusReader.new(book: rules.statuses, overrides: merged_overrides)
        ExampleReader.each_in_document(data) do |example|
          ExampleReader.each_pair(example.value, example.json_path) do |key, value, _, at|
            next unless value.is_a?(String) && @lookup.role?(key, ROLE) && !known?(value)

            profile.warn(:status_missing_from_enum, t('missing_from_enum', status: value),
                         json_path: at)
            add(value, reader, at, first_field_path, key)
          end
        end
      end

      # Внутренний статус не может быть увереннее роли поля, из enum которого
      # он прочитан: словарь статусов знает, что DONE — это approved, но
      # `st` полем статуса назвали матчеры (RoleLookup#temper).
      def add(value, reader, at, field_path, name)
        return if known?(value)

        result = reader.call(value)
        profile.status_map << IR::StatusMapping.new(provider_status: value, json_path: at,
                                                    internal: @lookup.temper(result.derived, name))
        report(value, result, at, field_path) if result.derived.unknown?
      end

      def known?(value)
        profile.status_map.any? { |mapping| mapping.provider_status == value }
      end

      def report(value, result, at, field_path)
        key = MESSAGES.fetch(result.kind, 'unknown_message')
        overlay = field_path && t('overlay_fragment', path: field_path, status: value)
        profile.warn(:status_unmapped, t(key, evidence: result.derived.evidence),
                     json_path: at, suggested_overlay: overlay)
      end

      # Расширения всех полей статуса вместе — для статусов из примеров,
      # у которых своего поля нет.
      def merged_overrides
        @fields.map { |_, _, node, _| node[EXTENSION] }.grep(Hash).reverse.reduce({}, :merge)
      end

      def first_field_path
        @fields.first&.last
      end

      # Без поля статуса fetch_status и process_callback не смогут перевести
      # ответ во внутренний статус — это пробел контракта, не тишина.
      def no_field
        profile.warn(:contract_gap, t('field_missing_message'),
                     json_path: json_path('components', 'schemas'))
      end

      def t(key, **params)
        Texts.t("analyzers.status.#{key}", **params)
      end
    end
  end
end
