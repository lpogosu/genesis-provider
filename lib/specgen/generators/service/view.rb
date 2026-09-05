# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Представление для templates/service.rb.erb: всё, что шаблон
      # подставляет, — шапка, имена, константы, таблицы и методы строками.
      # Шаблон видит только этот объект; логика — в презентерах.
      class View
        DOC_WIDTH = Ruby::WIDTH - 4

        # @param profile [IR::ProviderProfile]
        # @param rules [Rules::Registry]
        # @param naming [Naming]
        def initialize(profile:, rules:, naming:)
          @ctx = Context.new(profile: profile, rules: rules, naming: naming)
          @http = Http.new(@ctx)
          @tables = Tables.new(@ctx)
          @ctx.parts_payload = Payload.new(@ctx)
          @ctx.parts_requisites = Requisites.new(@ctx)
          @parts = { payload: @ctx.parts_payload, requisites: @ctx.parts_requisites,
                     polling: Polling.new(@ctx, @http), callback: Callback.new(@ctx),
                     signature: Signature.new(@ctx), authorization: Authorization.new(@ctx),
                     creation: Creation.new(@ctx, @http, @ctx.parts_requisites),
                     precheck: Precheck.new(@ctx), extras: Extras.new(@ctx, @http),
                     tables: @tables, http: @http }
        end

        # @return [Binding] контекст рендеринга ERB
        def template_binding
          binding
        end

        # @return [Context] общий контекст презентеров — его же берёт
        #   INTEGRATION.md, чтобы документ и код читали IR одинаково
        def context
          @ctx
        end

        # @return [Hash{Symbol => Object}] презентеры сервиса по имени
        attr_reader :parts

        # @return [String] имя файла спецификации для шапки
        def spec_file
          info&.spec_file || '-'
        end

        # @return [String]
        def spec_version
          info&.spec_version || '-'
        end

        # @return [String]
        def oas_version
          info&.oas_version || '-'
        end

        # @return [String] заголовок спецификации или slug
        def provider_title
          info&.title || @ctx.naming.slug
        end

        # @return [String]
        def class_name
          @ctx.naming.class_name
        end

        # @return [String]
        def base_class
          @ctx.contract.base_class
        end

        # @return [String] slug провайдера — константа PROVIDER
        def provider_slug
          @ctx.naming.slug
        end

        # Ключи provider.credentials, которые читает сгенерированный сервис:
        # авторизация плюс секрет подписи, если спецификация описывает
        # вебхуки. INTEGRATION.md и fixtures.json берут список отсюда, а не
        # собирают его заново.
        # @return [Array<String>]
        def credential_keys
          keys = @parts[:authorization].credential_keys.map(&:to_s)
          keys << @parts[:signature].value(:secret_key).to_s if @ctx.profile.webhooks.any?
          keys.uniq
        end

        # @return [Array<String>] библиотеки stdlib, нужные сервису
        def requires
          list = %w[digest json openssl]
          list << 'uri' if @http.query_auth?
          list.sort
        end

        # @return [String] переменная окружения базового URL
        def base_url_env
          @ctx.base_url_env
        end

        # @return [String] URL песочницы, иначе первый сервер, иначе заглушка
        def sandbox_url
          @ctx.sandbox_url
        end

        # @return [Array<Array(String, String, Integer)>] константа таймаута,
        #   переменная окружения, значение по умолчанию
        def timeouts
          @ctx.timeouts
        end

        # @return [Array<String>] комментарий к BASE_URL, когда песочница не найдена
        def sandbox_comment
          return [] if @ctx.profile.servers.any?(&:sandbox?)

          key = @ctx.profile.servers.empty? ? 'servers_none' : 'sandbox_unknown'
          Ruby.comment(@ctx.t(key), width: DOC_WIDTH, prefix: '# TODO: ')
        end

        # @return [Array<Array(String, String, Array<String>)>] прочие
        #   скалярные константы: имя, литерал, комментарии
        def constants
          Constants.new(@ctx, @parts).all
        end

        # @return [Boolean] спецификация описывает уведомления
        def webhooks?
          @ctx.profile.webhooks.any?
        end

        # @return [Array<String>]
        def status_map_lines
          @tables.status_lines
        end

        # @return [Array<String>]
        def error_map_lines
          @tables.error_lines
        end

        # @return [Array<String>]
        def operation_error_lines
          @tables.operation_error_lines
        end

        # @return [Array<String>]
        def retry_policy_lines
          @tables.retry_lines
        end

        # @return [Array<String>] записи FAILURE_CODES: HTTP-код → код платформы
        def failure_code_lines
          @tables.failure_code_lines
        end

        # @return [Array<String>] записи FAILURE_CODES_BY_ACTION
        def failure_action_lines
          @tables.failure_action_lines
        end

        # @return [Array<String>]
        def event_map_lines
          @tables.event_lines
        end

        # @return [Array<Method>] четыре метода контракта в порядке справочника
        def contract_methods
          by_name = [@parts[:precheck], @parts[:creation], @parts[:callback], @parts[:polling]]
                    .filter_map(&:method).to_h { |method| [method.name, method] }
          @ctx.contract.method_names.filter_map { |name| by_name[name] }
        end

        # @return [Array<Method>] операции вне контракта
        def extra_methods
          @parts[:extras].methods
        end

        # Публичный верификатор подписи. Он публичный, потому что подпись
        # считается по сырым байтам тела, а process_callback получает уже
        # разобранный JSON: вызвать проверку обязан маршрут вебхука до
        # разбора. Спецификация без уведомлений его не получает.
        # @return [Array<Method>]
        def webhook_methods
          webhooks? ? [@parts[:signature].public_method] : []
        end

        # @return [Array<Method>]
        def helper_methods
          Privates.new(@ctx, @parts).methods
        end

        # @param lines [Array<String>]
        # @param depth [Integer]
        # @return [String] строки с отступом, склеенные переводами строк
        def indent(lines, depth)
          Ruby.indent(Ruby.tidy(lines), depth).join("\n")
        end

        private

        def info
          @ctx.profile.info
        end
      end
    end
  end
end
