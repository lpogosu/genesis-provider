# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Тело запроса из ролей полей схемы: для каждого поля с ролью —
      # выражение платформы из rules/contract.yml, для вложенного объекта —
      # вложенный хеш по полям его схемы.
      #
      # Поле без роли — по правилу CLAUDE.md «Что генерируем при неполной
      # спеке»: обязательное попадает в payload с лучшим, что есть (пример
      # из спецификации, иначе nil), и TODO с типом, ограничениями,
      # обоснованием и подсказкой, где закрепить роль; необязательное
      # пропускается. Роль ниже порога остаётся в коде с комментарием об
      # уверенности — инструмент решает сам, человек проверяет по отчёту.
      class Payload
        # Одна запись хеша: комментарии над ней и её строки.
        Entry = Struct.new(:comments, :lines, keyword_init: true)
        # Ширина строки внутри build_payload: отступ тела метода плюс хеш.
        BASE_INDENT = 8
        MAX_DEPTH = 6

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
        end

        # @param schema_name [String, nil] схема тела запроса
        # @return [Array<String>, nil] строки записей хеша без внешних скобок;
        #   nil, если схемы нет
        def lines(schema_name)
          schema = @ctx.schema(schema_name)
          return nil if schema.nil?

          render(entries(schema, [schema_name], 0))
        end

        private

        def render(entries)
          entries.each_with_index.flat_map do |entry, index|
            body = entry.lines.dup
            body[-1] = "#{body[-1]}," unless index == entries.size - 1
            entry.comments + body
          end
        end

        def entries(schema, visited, depth)
          schema.fields.filter_map { |field| entry(field, visited, depth) }
        end

        def entry(field, visited, depth)
          return array(field, depth) if field.type == 'array'
          return object(field, visited, depth) if field.schema

          scalar(field, depth)
        end

        def scalar(field, depth)
          expression = expression_for(field.role)
          if expression
            Entry.new(comments: doubts(field, depth), lines: [entry_line(field, expression)])
          elsif needed?(field)
            todo(field, depth)
          end
        end

        def entry_line(field, value)
          "#{Ruby.key(field.name)} #{value}"
        end

        def object(field, visited, depth)
          inner = nested_lines(field, visited, depth)
          return nil if inner.nil? || (inner.empty? && !needed?(field))
          return Entry.new(comments: [], lines: [entry_line(field, '{}')]) if inner.empty?

          Entry.new(comments: doubts(field, depth),
                    lines: [entry_line(field, '{'), *Ruby.indent(inner, 2), '}'])
        end

        # @return [Array<String>, nil] nil, если схемы нет, она уже
        #   раскрыта выше по дереву или вложенность слишком глубока
        def nested_lines(field, visited, depth)
          nested = @ctx.schema(field.schema)
          return nil if nested.nil? || visited.include?(field.schema) || depth >= MAX_DEPTH

          render(entries(nested, visited + [field.schema], depth + 1))
        end

        def array(field, depth)
          return nil unless needed?(field)

          note = @ctx.t('todo_array', item: field.schema || field.type.to_s)
          Entry.new(comments: comment(note, depth, prefix: '# TODO: '),
                    lines: ["#{Ruby.key(field.name)} []"])
        end

        # Платформа хранит сумму в мажорных единицах; провайдер ждёт свои —
        # роль amount единственная, чьё значение проходит через пересчёт.
        def expression_for(role)
          return nil unless role.known?

          expression = @ctx.accessor(role.value)
          return expression unless expression && role.value == :amount

          "to_provider_units(#{expression})"
        end

        def needed?(field)
          field.required? || field.conditionally_required?
        end

        # Комментарии над записью: уверенность ниже порога и условная
        # обязательность.
        def doubts(field, depth)
          lines = []
          if @ctx.doubtful?(field.role)
            lines.concat(comment(@ctx.t('role_doubt', role: field.role.value,
                                                      confidence: @ctx.source_label(field.role),
                                                      evidence: field.role.evidence), depth))
          end
          lines.concat(comment(required_when(field), depth)) if field.conditionally_required?
          lines
        end

        def required_when(field)
          rule = field.required_when
          origin = "#{Texts.t("origin.#{rule.origin}")} #{format('%.2f', rule.confidence)}"
          key = rule.presence? ? 'required_when_present' : 'required_when_equals'
          @ctx.t(key, field: rule.field, origin: origin, value: rule.values.join(', '))
        end

        def todo(field, depth)
          value = field.example.nil? ? 'nil' : Ruby.literal(field.example)
          Entry.new(comments: todo_comments(field, depth), lines: [entry_line(field, value)])
        end

        def todo_comments(field, depth)
          head = @ctx.t(field.role.known? ? 'todo_no_accessor' : 'todo_role_unknown',
                        role: field.role.value, requirement: requirement(field))
          comment(head, depth, prefix: '# TODO: ') +
            todo_details(field).flat_map { |text| comment(text, depth, prefix: '#   ') }
        end

        def todo_details(field)
          [@ctx.t('todo_shape', shape: shape(field)),
           field.description && @ctx.t('todo_description', text: field.description),
           @ctx.t('todo_evidence', evidence: field.role.evidence),
           @ctx.t('todo_fill')].compact
        end

        def requirement(field)
          field.required? ? @ctx.t('required') : @ctx.t('conditionally_required')
        end

        # "string, enum: [a, b], maxLength: 12" — ограничения в терминах
        # JSON Schema, как их написал автор спецификации.
        def shape(field)
          parts = [[field.type, field.format].compact.join(' ')]
          field.constraints.each do |key, value|
            parts << "#{camel(key)}: #{Reporter::Format.constraint(value)}"
          end
          parts.reject(&:empty?).join(', ')
        end

        def camel(key)
          key.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
        end

        def comment(text, depth, prefix: '# ')
          Ruby.comment(text, width: Ruby::WIDTH - BASE_INDENT - (depth * 2), prefix: prefix)
        end
      end
    end
  end
end
