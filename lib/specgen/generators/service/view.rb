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
          @parts = { payload: Payload.new(@ctx), polling: Polling.new(@ctx, @http),
                     callback: Callback.new(@ctx), signature: Signature.new(@ctx),
                     authorization: Authorization.new(@ctx), creation: Creation.new(@ctx, @http),
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
          list = [amount_constant, ['DEFAULT_ERROR_ACTION', default_error_action, []]]
          list << ['DEDUP_STATUS', dedup_status.to_s, []] if dedup_status
          list.concat(idempotency_constants)
          list << ['CANCELLABLE_STATUSES', "#{Ruby.literal(cancellable)}.freeze", []] if cancellable
          list + @parts[:signature].constants
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

        def default_error_action
          Ruby.sym(@ctx.rules.errors.default_action)
        end

        def dedup_status
          idempotency = @ctx.profile.idempotency
          idempotency&.dedup? ? idempotency.conflict_status.value : nil
        end

        def cancellable
          @parts[:extras].cancellable_statuses
        end

        def amount_constant
          units = @ctx.profile.units
          return ['AMOUNT_MULTIPLIER', units.multiplier.to_s, units_comment(units)] if units&.known?

          evidence = units.nil? ? @ctx.t('units_none') : units.unit.evidence
          text = @ctx.t('units_unknown', evidence: evidence)
          ['AMOUNT_MULTIPLIER', '1', Ruby.comment(text, width: DOC_WIDTH, prefix: '# TODO: ')]
        end

        def units_comment(units)
          text = @ctx.t('units_comment', unit: units.unit.value, evidence: units.exponent.evidence,
                                         currency: units.currency.value.to_s)
          Ruby.comment(text, width: DOC_WIDTH)
        end

        def idempotency_constants
          idempotency = @ctx.profile.idempotency
          return [] unless idempotency&.supported?

          header = @ctx.t('idempotency_comment', evidence: idempotency.header.evidence)
          [['IDEMPOTENCY_HEADER', Ruby.str(idempotency.header.value),
            Ruby.comment(header, width: DOC_WIDTH)],
           ['IDEMPOTENCY_NAMESPACE', Ruby.str(@ctx.rules.idempotency.namespace),
            Ruby.comment(@ctx.t('namespace_comment'), width: DOC_WIDTH)]]
        end
      end
    end
  end
end
