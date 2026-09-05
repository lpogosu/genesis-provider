# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Ответы провайдера: по фикстуре на каждый объявленный код ответа
      # каждой операции, и по одной на каждый именованный пример этого кода.
      #
      # `expected` — то, чего ждёт платформа: успешный ответ переводится в
      # внутренний статус по STATUS_MAP, ошибочный — в действие по ERROR_MAP
      # (те же таблицы, что в константах сервиса), ответ с кодом конфликта у
      # операции создания помечается dedup.
      class Responses < Base
        # @return [Array<Hash>] фикстуры в порядке спецификации
        def all
          ctx.profile.operations.flat_map do |operation|
            operation.responses.flat_map { |response| fixtures(operation, response) }
          end
        end

        private

        def fixtures(operation, response)
          if response.examples.empty?
            built = body_from({}, response.schema, t('no_response_example'))
            return [fixture(operation, response, built)]
          end

          response.examples.map do |name, value|
            fixture(operation, response, body_from({ name => value }, response.schema, ''))
          end
        end

        def fixture(operation, response, body)
          notes = []
          notes << t('status_range', status: response.status) if response.code.nil?
          notes << t('no_error_responses') if only_success?(operation) && response.success?
          { 'name' => name_of(operation, response, body), 'operation' => operation.key,
            'status' => response.code || response.status, 'body' => body.value,
            'expected' => expected(operation, response, body) }
            .merge(tail(body, notes))
        end

        def name_of(operation, response, body)
          base = "#{operation.key} #{response.status}"
          named?(body) ? "#{base} (#{body.name})" : base
        end

        # @return [Boolean] спецификация объявила у операции только успех
        def only_success?(operation)
          operation.responses.all?(&:success?)
        end

        def expected(operation, response, body)
          return dedup(response, body.value) if dedup?(operation, response)
          return success(response, body.value) if response.success?

          { 'action' => action_for(response, body).to_s }
        end

        # Повтор с тем же ключом идемпотентности: код конфликта несёт схему
        # успешного ответа, сервис подхватывает существующую операцию.
        def dedup?(operation, response)
          idempotency = ctx.profile.idempotency
          create = ctx.create_operation
          return false unless idempotency&.dedup? && create && operation.key == create.key

          idempotency.conflict_status.value.to_s == response.status
        end

        def dedup(response, value)
          { 'dedup' => true }.merge(success(response, value))
        end

        # Успех: внутренний статус по полю статуса тела; тела без статуса
        # операцию не двигают.
        def success(response, value)
          path = ctx.role_path(response.schema, :status)
          raw = Values.dig_path(value, path)
          return { 'result' => 'success' } if raw.nil?

          { 'internal_status' => internal_status(raw) }
        end

        def internal_status(raw)
          mapping = ctx.profile.status_map.find { |item| item.provider_status == raw.to_s }
          mapping&.mapped? ? mapping.internal.value.to_s : nil
        end

        # Тот же порядок, что у provider_failure сервиса: код ошибки из тела,
        # затем HTTP-код, затем действие по умолчанию.
        def action_for(response, body)
          rule = rule_for(spec_code(response, body), response.code)
          rule ? rule.action.value : ctx.rules.errors.default_action
        end

        # Код ошибки читается из тела только тогда, когда тело — пример из
        # спецификации: код, подставленный нами из enum, о политике ничего не
        # говорит, и действие тогда определяет HTTP-код.
        def spec_code(response, body)
          return nil unless body.source == SPEC_EXAMPLE

          Values.dig_path(body.value, ctx.role_path(response.schema, :error_code))
        end

        # @return [IR::ErrorRule, nil] правило по коду ошибки, иначе по HTTP-коду
        def rule_for(code, status)
          parts[:tables].code_rules.find { |rule| rule.provider_code == code.to_s } ||
            parts[:tables].http_rules.find { |rule| rule.http_status == status }
        end
      end
    end
  end
end
