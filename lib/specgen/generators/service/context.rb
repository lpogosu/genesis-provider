# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Общее для всех презентеров сервиса: профиль, справочники, имена и
      # выборки из IR, которые нужны нескольким частям шаблона. Всё, что
      # презентеры спрашивают у контракта — имена хелперов, выражения
      # платформы, порог матчеров, — проходит здесь, чтобы ни один литерал
      # имени не попал в шаблон.
      class Context
        # @return [IR::ProviderProfile]
        attr_reader :profile
        # @return [Rules::Registry]
        attr_reader :rules
        # @return [Naming]
        attr_reader :naming

        # @param profile [IR::ProviderProfile]
        # @param rules [Rules::Registry]
        # @param naming [Naming]
        def initialize(profile:, rules:, naming:)
          @profile = profile
          @rules = rules
          @naming = naming
        end

        # Таймауты клиента: константа сервиса, переменная окружения и
        # значение по умолчанию в секундах. Одна таблица для service.rb и
        # INTEGRATION.md, чтобы имена не набирались строками дважды.
        TIMEOUTS = [['OPEN_TIMEOUT', 5], ['READ_TIMEOUT', 15]].freeze
        # Базовый URL, когда спецификация не объявила ни одного сервера.
        BASE_URL_PLACEHOLDER = 'https://TODO.example'

        # @return [Rules::ContractBook]
        def contract
          rules.contract
        end

        # @return [Array<Array(String, String, Integer)>] константа,
        #   переменная окружения, значение по умолчанию
        def timeouts
          TIMEOUTS.map { |name, default| [name, naming.env(name), default] }
        end

        # @return [String] переменная окружения базового URL
        def base_url_env
          env = profile.info&.base_url_env
          env&.known? ? env.value : naming.env_name
        end

        # @return [IR::Server, nil] сервер, который станет BASE_URL по
        #   умолчанию: песочница, иначе первый объявленный
        def default_server
          profile.servers.find(&:sandbox?) || profile.servers.first
        end

        # @return [String] URL песочницы, иначе первого сервера, иначе заглушка
        def sandbox_url
          default_server&.url || BASE_URL_PLACEHOLDER
        end

        # @return [Rules::PlatformBindings]
        def platform
          contract.platform
        end

        # @return [String] полное имя сгенерированного класса в пространстве
        #   имён базового класса: "Provider::AcmePayService"
        def full_class_name
          namespace = contract.base_class.to_s.rpartition('::').first
          namespace.empty? ? naming.class_name : "#{namespace}::#{naming.class_name}"
        end

        # @return [IR::Operation, nil] операция создания: выплата, иначе депозит
        def create_operation
          profile.operation_for(:create_payout) || profile.operation_for(:create_deposit)
        end

        # @return [IR::Operation, nil]
        def status_operation
          profile.operation_for(:fetch_status)
        end

        # @return [IR::Webhook, nil] первый вебхук спецификации
        def webhook
          profile.webhooks.first
        end

        # @param name [String, nil]
        # @return [IR::Schema, nil]
        def schema(name)
          name && profile.schema(name)
        end

        # @param key [Symbol] смысловой ключ хелпера контракта
        # @return [String] имя метода Ruby
        def helper(key)
          contract.helper(key)
        end

        # @param code [Symbol, String] символьный код отказа
        # @return [String] "failure(:code, 'errors.code')"
        def failure(code)
          "#{helper(:failure)}(#{Ruby.sym(code)}, #{Ruby.str("errors.#{code}")})"
        end

        # @return [String] выражение успешного результата
        def success
          helper(:success)
        end

        # @param role [Symbol]
        # @return [String, nil] выражение платформы для роли
        def accessor(role)
          role && platform.accessor(role)
        end

        # @return [Float] порог отчёта у матчеров ролей
        def threshold
          rules.roles.scoring(:threshold)
        end

        # @param derived [IR::Derived]
        # @return [Boolean] решение ниже порога, о нём стоит сказать в коде
        def doubtful?(derived)
          derived.source == :heuristic && derived.confidence < threshold
        end

        # @param derived [IR::Derived]
        # @return [String] "задано явно 1.00" — как в сводке
        def source_label(derived)
          "#{Texts.t("source.#{derived.source}")} #{format('%.2f', derived.confidence)}"
        end

        # Запись справочника rules/auth.yml, описывающая авторизацию профиля.
        # @return [Hash, nil]
        def auth_scheme
          auth = profile.auth
          return nil if auth.nil? || auth.type.unknown? || auth.none?

          auth_entries.find do |entry|
            entry[:ir_type] == auth.type.value && entry[:location] == auth.location
          end
        end

        # Путь к полю с ролью внутри схемы, через вложенные объекты.
        # @param schema_name [String, nil]
        # @param role [Symbol]
        # @return [Array<String>, nil] имена полей от корня к полю
        def role_path(schema_name, role, visited = [])
          schema = schema(schema_name)
          return nil if schema.nil? || visited.include?(schema_name)

          direct = schema.fields.find { |field| field.role.value == role }
          return [direct.name] if direct

          nested_path(schema, role, visited + [schema_name])
        end

        # Путь к коду ошибки в теле ответа: по любому ответу любой операции.
        # По нему provider_failure читает код, а INTEGRATION.md знает, какой
        # ключ локализации получит отказ.
        # @return [Array<String>, nil]
        def error_code_path
          profile.operations.each do |operation|
            operation.responses.each do |response|
              path = role_path(response.schema, :error_code)
              return path if path
            end
          end
          nil
        end

        # @param variable [String] имя переменной с разобранным телом
        # @param path [Array<String>]
        # @return [String] "body['status']" или "body.dig('error', 'code')"
        def dig(variable, path)
          return "#{variable}[#{Ruby.str(path.first)}]" if path.size == 1

          "#{variable}.dig(#{path.map { |key| Ruby.str(key) }.join(', ')})"
        end

        # @param key [String] ключ под generators.service
        # @return [String]
        def t(key, **params)
          Texts.t("generators.service.#{key}", **params)
        end

        private

        def auth_entries
          book = rules.auth
          book.names.map { |name| book.scheme(name) }
        end

        def nested_path(schema, role, visited)
          schema.fields.each do |field|
            next if field.schema.nil? || field.type == 'array'

            nested = role_path(field.schema, role, visited)
            return [field.name, *nested] if nested
          end
          nil
        end
      end
    end
  end
end
