# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 9, часть вторая: допущения конкретного прогона, связанные со
      # схемами и условиями — роль поля ниже порога, обязательное поле без
      # роли, условная обязательность из прозы, условие из прозы, параметр
      # пути без роли, поле статуса или события, найденное не по роли.
      # Только то, что превратилось в код; остальное — в report.md.
      class RunAssumptions < Base
        MAX_DEPTH = Service::Payload::MAX_DEPTH

        # @return [Array<String>]
        def lines
          field_lines + condition_lines + path_lines + lookup_lines
        end

        private

        def precheck
          parts[:precheck]
        end

        # Поля схемы тела запроса операции создания, рекурсивно, как их
        # обходит Service::Payload.
        def field_lines
          schema = ctx.create_operation&.request_schema
          return [] if schema.nil?

          walk(ctx.schema(schema), [], [schema], 0)
        end

        def walk(schema, prefix, visited, depth)
          return [] if schema.nil? || depth >= MAX_DEPTH

          schema.fields.flat_map do |field|
            path = [*prefix, field.name]
            next scalar(field, path) unless nested?(field, visited)

            walk(ctx.schema(field.schema), path, visited + [field.schema], depth + 1)
          end
        end

        def nested?(field, visited)
          field.schema && field.type != 'array' && !visited.include?(field.schema)
        end

        def scalar(field, path)
          lines = []
          lines << doubt(field, path) if ctx.doubtful?(field.role)
          lines << unknown(field, path) if unknown_but_needed?(field)
          lines << required_when(field) if hinted?(field)
          lines
        end

        def unknown_but_needed?(field)
          field.role.unknown? && field.schema.nil? &&
            (field.required? || field.conditionally_required?)
        end

        def hinted?(field)
          field.conditionally_required? && !field.required_when.formal?
        end

        def doubt(field, path)
          t('run_field_doubt', path: path.join('.'), role: field.role.value,
                               confidence: label(field.role), evidence: field.role.evidence)
        end

        def unknown(field, path)
          value = field.example.nil? ? 'nil' : Ruby.literal(field.example)
          t('run_field_unknown', path: path.join('.'), value: code(value),
                                 evidence: field.role.evidence)
        end

        def required_when(field)
          rule = field.required_when
          t('run_required_when', field: field.name, condition: when_text(rule),
                                 origin: Texts.t("origin.#{rule.origin}"),
                                 confidence: format('%.2f', rule.confidence))
        end

        def when_text(rule)
          return t('run_when_present', field: rule.field) if rule.presence?

          "#{rule.field} = #{rule.values.join(', ')}"
        end

        # Условия, прочитанные из прозы: описание — то же, что в комментарии
        # сервиса над проверкой.
        def condition_lines
          profile.conditions.select(&:heuristic?).map do |condition|
            t('run_condition', kind: condition.kind, description: describe(condition))
          end
        end

        def describe(condition)
          checked = Service::Precheck::CHECKED.include?(condition.kind)
          return precheck.description(condition) if checked

          "#{Reporter::Format.constraint(condition.value.value)} (#{label(condition.value)})"
        end

        # Параметры пути без роли у операций, которые ходят к провайдеру:
        # Service::Http подставляет идентификатор провайдера с TODO.
        def path_lines
          profile.operations.reject { |op| op.role.value == :webhook }.flat_map do |operation|
            operation.parameters_in(:path).reject { |p| p.role.known? }.map do |parameter|
              t('run_path_param', name: parameter.name, key: operation.key)
            end
          end
        end

        # Поле статуса в ответе опроса и поле события в уведомлении, когда
        # их не нашли по ролям.
        def lookup_lines
          lines = []
          if ctx.status_operation && parts[:polling].status_path.nil?
            lines << t('run_status_field', key: ctx.status_operation.key)
          end
          lines << t('run_event_field') if event_field_missing?
          lines << t('run_provider_id') if provider_id_missing?
          lines
        end

        def event_field_missing?
          webhook = ctx.webhook
          return false if webhook.nil? || parts[:callback].event_field

          ctx.role_path(webhook.schema, :status).nil?
        end

        def provider_id_missing?
          create = ctx.create_operation
          return false if create.nil?

          create.success_responses.none? { |r| ctx.role_path(r.schema, :provider_operation_id) }
        end
      end
    end
  end
end
