# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Запросы к провайдеру: по одной фикстуре на каждую операцию
      # спецификации, включая операции без тела и точку приёма уведомлений.
      #
      # Форма выбрана под WebMock без переупаковки:
      #   stub_request(f['method'].to_sym, base_url + f['path'])
      #     .with(body: f['body'], headers: f['headers'])
      class Requests < Base
        # Заглушки в данных фикстуры: только ASCII, только очевидно
        # ненастоящие — путь и ключ идемпотентности читает машина.
        PATH_PLACEHOLDER = 'test_id'
        OPERATION_PLACEHOLDER = 'test_operation_id'

        # @return [Array<Hash>] фикстуры в порядке спецификации
        def all
          ctx.profile.operations.map { |operation| fixture(operation) }
        end

        private

        def fixture(operation)
          body = body_from(operation.request_examples, operation.request_schema,
                           t('no_request_example'))
          notes = []
          path = request_path(operation, notes)
          notes << t('auth_computed') if auth_computed?
          head(operation, path, body).merge(raw_body(operation, body)).merge(tail(body, notes))
        end

        def head(operation, path, body)
          { 'name' => operation.key, 'role' => operation.role.value.to_s,
            'method' => operation.http_method.to_s, 'path' => path,
            'headers' => headers(operation, body), 'body' => body.value }
        end

        # Точные байты тела нужны там, где по ним считается подпись: без них
        # заголовок подписи нечем проверить.
        def raw_body(operation, body)
          return {} unless signed?(operation, body)

          { 'raw_body' => ::JSON.generate(body.value) }
        end

        # Путь с подставленными примерами параметров: свой `example`
        # параметра, иначе пример поля с той же ролью из любой схемы, иначе
        # заглушка и строка в "_todo".
        def request_path(operation, notes)
          operation.path.gsub(Service::Http::PATH_PARAM) do
            name = Regexp.last_match(1)
            parameter = operation.parameters_in(:path).find { |item| item.name == name }
            value = path_value(parameter)
            notes << t('path_param_synthesized', name: name) if value.nil?
            (value || PATH_PLACEHOLDER).to_s
          end
        end

        def path_value(parameter)
          return nil if parameter.nil?
          return parameter.example unless parameter.example.nil?

          role = parameter.role.known? ? parameter.role.value : nil
          values.role_example(role) || values.role_example(:provider_operation_id)
        end

        # Заголовки ровно те, что отправляет сгенерированный сервис:
        # авторизация, тип содержимого, ключ идемпотентности у операции
        # создания и подпись у входящего уведомления.
        def headers(operation, body)
          result = {}
          result[CONTENT_TYPE] = operation.request_media_type unless body.value.nil?
          result.merge!(auth_headers) if operation.secured
          result.merge!(idempotency_header(operation, body))
          result.merge!(signature_header(operation, body))
          result.sort.to_h
        end

        def idempotency_header(operation, body)
          idempotency = ctx.profile.idempotency
          create = ctx.create_operation
          return {} unless idempotency&.supported? && create && operation.key == create.key

          { idempotency.header.value.to_s => key_for(operation, body) }
        end

        # Тот же ключ, что посчитает idempotency_key_for сервиса, если
        # operation.id платформы равен external_id из примера.
        def key_for(operation, body)
          reference = operation_reference(operation, body)
          return reference if ctx.profile.idempotency.strategy.value == :external_id

          Uuid.v5(ctx.rules.idempotency.namespace, "#{ctx.naming.slug}:#{reference}")
        end

        def operation_reference(operation, body)
          path = ctx.role_path(operation.request_schema, :external_id)
          found = Values.dig_path(body.value, path)
          (found || values.role_example(:external_id) || OPERATION_PLACEHOLDER).to_s
        end

        def signature_header(operation, body)
          return {} unless signed?(operation, body)

          signing.headers(::JSON.generate(body.value))
        end

        # @return [Boolean] запрос подписывает провайдер, а не мы: это
        #   входящее уведомление
        def signed?(operation, body)
          operation.role.value == :webhook && !body.value.nil? && signing.known?
        end
      end
    end
  end
end
