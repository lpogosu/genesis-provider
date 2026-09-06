# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Опрос статуса: каждый статус провайдера обязан дойти до своего
      # хелпера платформы, а объявленный код ошибки — до кода отказа.
      #
      # Статусов у операции обычно больше, чем примеров ответа: пример один, а
      # STATUS_MAP печатает все. Поэтому тело примера берётся как основа, и в
      # него подставляется каждый статус таблицы — иначе прогон доказывал бы
      # перевод одной строки таблицы из пяти.
      class Polling < Base
        # @return [Array<Finding>]
        def call
          return [] if spec.nil?

          self.method_name = spec.name
          return [unchecked(t('aspect_request'), t('run_no_status'))] if operation_of.nil?
          return [unchecked(t('aspect_request'), t('run_no_fixture'))] if response.nil?

          statuses + failures
        end

        private

        def spec
          @spec ||= ctx.contract.method_for(:fetch_status)
        end

        def operation_of
          ctx.status_operation
        end

        def response
          @response ||= fixtures.success_response(operation_of.key, codes) if operation_of
        end

        def codes
          parts[:http].success_codes(operation_of)
        end

        # Сначала пример как есть — с тем внутренним статусом, который обещает
        # фикстура; потом остальные статусы таблицы подстановкой.
        def statuses
          declared = response.dig('expected', 'internal_status')
          first = declared ? [check(response['body'], declared, raw_status.to_s)] : []
          first + substituted(declared ? [raw_status.to_s] : [])
        end

        # Подстановка возможна, только если поле статуса в теле примера есть:
        # иначе замена молча не состоится и прогон проверит не тот статус.
        def substituted(covered)
          return [] if parts[:polling].status_path.nil? || raw_status.nil?

          rest = parts[:tables].status_mappings.select(&:mapped?)
                               .reject { |item| covered.include?(item.provider_status.to_s) }
          rest.map { |item| substituted_check(item) }
        end

        def substituted_check(mapping)
          body = with_status(parts[:polling].status_path, mapping.provider_status)
          check(body, mapping.internal.value, mapping.provider_status.to_s)
        end

        # @return [Object, nil] статус провайдера в теле примера
        def raw_status
          Generators::Fixtures::Values.dig_path(response['body'], parts[:polling].status_path)
        end

        def with_status(path, value)
          body = Generators::Fixtures::Values.dup_value(response['body'])
          Generators::Fixtures::Values.assign(body, path, value)
          body
        end

        # Один статус: вызов обязан кончиться успехом и позвать ровно тот
        # хелпер, который назначен внутреннему статусу.
        def check(body, internal, label)
          aspect = t('aspect_status', status: label.empty? ? internal : label)
          client.body(response['status'], body)
          result, error = invoke(spec.name, *contract_args(spec))
          return crashed(aspect, error) if error

          verify(aspect) { judge.success(result) || judge.helper(internal) }
        end

        # Объявленные коды ошибок опроса, включая отсутствие операции.
        def failures
          fixtures.responses(operation_of.key).filter_map do |fixture|
            code = fixture.dig('expected', 'failure_code')
            next if code.nil?

            attempt(fixture, code)
          end
        end

        def attempt(fixture, code)
          aspect = t('aspect_response', status: fixture['status'])
          client.reply(operation: operation_of.key, status: fixture['status'])
          result, error = invoke(spec.name, *contract_args(spec))
          return crashed(aspect, error) if error

          verify(aspect) { judge.failure(result, code: code) }
        end
      end
    end
  end
end
