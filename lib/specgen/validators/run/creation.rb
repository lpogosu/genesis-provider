# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Создание операции: успешный путь, каждый объявленный код ошибки и
      # успешный путь дедупликации.
      #
      # Проверяется всё, что сервис обязан сделать сам: адрес и метод,
      # заголовок авторизации со значением из учётных данных, ключ
      # идемпотентности, тело запроса и идентификатор, который платформа
      # сохранит как provider_operation_key.
      class Creation < Base
        # @return [Array<Finding>]
        def call
          return [] if spec.nil?

          self.method_name = spec.name
          problem = missing_input
          return [unchecked(t('aspect_request'), problem)] if problem

          happy + failures + dedup
        end

        private

        # @return [String, nil] почему звать нечего
        def missing_input
          return t('run_no_create') if operation_of.nil?
          return t('run_no_fixture') if request.nil?

          nil
        end

        def spec
          @spec ||= ctx.contract.method_for(:create_payout) ||
                    ctx.contract.method_for(:create_deposit)
        end

        def operation_of
          ctx.create_operation
        end

        def request
          @request ||= fixtures.request(operation_of.key) if operation_of
        end

        def codes
          parts[:http].success_codes(operation_of)
        end

        def response
          @response ||= fixtures.success_response(operation_of.key, codes)
        end

        # Успешный путь: один вызов клиента и всё, что в нём должно быть.
        def happy
          client.reply(operation: operation_of.key, status: success_status)
          result, error = invoke(spec.name, *contract_args(spec))
          return [crashed(t('aspect_request'), error)] if error

          [call_finding, *auth_findings, *idempotency_finding, body_finding,
           result_finding(result), *status_finding]
        end

        def success_status
          response&.dig('status') || codes.first
        end

        def call_finding
          verify(t('aspect_call', verb: verb, path: request['path'])) do
            judge.request(verb: operation_of.http_method, template: operation_of.path,
                          path: request['path'])
          end
        end

        def verb
          operation_of.http_method.to_s.upcase
        end

        # Заголовки авторизации проверяются по значению: секрет приходит из
        # provider.credentials, и подстановка учётных данных — часть работы
        # сгенерированного класса. Значение, которое класс вычисляет сам
        # (токен OAuth2, подпись запроса), сверять не с чем: в фикстуре стоит
        # раскрытая часть выражения, а в прогоне — заглушка.
        def auth_findings
          auth = parts[:authorization]
          return [] if auth.query?

          auth.param_names.map do |name|
            aspect = t('aspect_auth', header: name)
            expected = header_value(name)
            next unchecked(aspect, computed(auth)) if auth.stub_name
            next unchecked(aspect, t('run_no_header_fixture')) if expected.nil?

            verify(aspect) { judge.header(name, expected) }
          end
        end

        def computed(auth)
          t('run_auth_computed', method: auth.stub_name)
        end

        # Ключ идемпотентности сверяется с посчитанным здесь UUID v5, а не с
        # заголовком фикстуры: проверяется, что класс считает его
        # детерминированно от operation.id, а не что две записи одного
        # примера совпали.
        def idempotency_finding
          idempotency = ctx.profile.idempotency
          return [] unless idempotency&.supported?

          name = idempotency.header.value.to_s
          expected = run.payment.idempotency_key
          [verify(t('aspect_idempotency', header: name)) { judge.header(name, expected) }]
        end

        def header_value(name)
          headers = request['headers']
          return nil unless headers.is_a?(Hash)

          headers.find { |key, _value| key.to_s.casecmp?(name.to_s) }&.last
        end

        def body_finding
          body = request['body']
          aspect = t('aspect_body')
          return unchecked(aspect, t('run_no_body')) unless body.is_a?(Hash)

          verify(aspect) { judge.body(body, required: required_paths) }
        end

        # Пути обязательных полей схемы тела запроса через точку. Только по
        # ним отсутствие ключа считается расхождением: необязательное поле без
        # роли генератор не отправляет намеренно.
        def required_paths(name = operation_of.request_schema, prefix = [], visited = [])
          schema = ctx.schema(name)
          return [] if schema.nil? || visited.include?(name)

          schema.fields.flat_map do |field|
            at = [*prefix, field.name]
            needed = field.required? || field.conditionally_required?
            (needed ? [at.join('.')] : []) + required_paths(field.schema, at, [*visited, name])
          end
        end

        # Идентификатор операции у провайдера в результате: платформа берёт
        # его как payload.dig(:result, :id).
        def result_finding(result)
          expected = run.payment.provider_key
          aspect = t('aspect_result')
          return unchecked(aspect, t('run_no_id_path')) if expected.nil?

          verify(aspect) { judge.result_id(result, expected) }
        end

        # Статус из ответа на создание обязан дойти до хелпера платформы.
        def status_finding
          internal = response&.dig('expected', 'internal_status')
          return [] if internal.nil?

          [verify(t('aspect_status', status: internal)) { judge.helper(internal) }]
        end

        # Каждый объявленный код ошибки: код отказа платформы обязан совпасть
        # с тем, что обещает fixtures.json и таблица INTEGRATION.md.
        def failures
          fixtures.responses(operation_of.key).filter_map do |fixture|
            code = fixture.dig('expected', 'failure_code')
            next if code.nil?

            attempt(fixture, t('aspect_response', status: fixture['status'])) do |result|
              judge.failure(result, code: code)
            end
          end
        end

        # Ответ с кодом конфликта, чья схема совпадает со схемой успеха, —
        # успешный путь по draft-ietf-httpapi-idempotency-key-header, а не
        # отказ: сервис подхватывает уже созданную операцию.
        def dedup
          fixtures.responses(operation_of.key).filter_map do |fixture|
            next unless fixture.dig('expected', 'dedup')

            attempt(fixture, t('aspect_dedup', status: fixture['status'])) do |result|
              judge.success(result)
            end
          end
        end

        def attempt(fixture, aspect)
          client.reply(operation: operation_of.key, status: fixture['status'])
          result, error = invoke(spec.name, *contract_args(spec))
          return crashed(aspect, error) if error

          verify(aspect) { yield(result) }
        end
      end
    end
  end
end
