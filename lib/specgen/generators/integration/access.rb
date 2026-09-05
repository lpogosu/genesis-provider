# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Разделы 1 и 2: авторизация с местом хранения секрета и переменные
      # окружения. Тип и заголовки — из Service::Authorization, имена ENV и
      # таймауты — из Service::Context, ровно те, что напечатаны в сервисе.
      class Access < Base
        # @return [Array<String>] абзацы раздела об авторизации
        def auth_lines
          auth = profile.auth
          helper = code(ctx.helper(:auth_headers))
          return [t('auth_none', helper: helper, report: report)] if auth.nil? || auth.none?
          unless authorization.recognised?
            return [t('auth_unknown', scheme: auth.scheme_name, helper: helper, report: report)]
          end

          [type_line(auth), where_line, stub_line].compact
        end

        # @return [Array<String>] таблица ключей provider.credentials
        def credential_rows
          rows = authorization.credential_keys.map do |key|
            [code("provider.credentials[:#{key}]"), code(ctx.helper(:auth_headers)), t('cred_auth')]
          end
          rows << signature_row if profile.webhooks.any?
          rows
        end

        # @return [Array<Array<String>>] переменная, назначение, дефолт,
        #   обязательна ли
        def env_rows
          rows = [[code(ctx.base_url_env), t('env_base_url'), base_url_default, t('not_required')]]
          ctx.timeouts.each do |constant, env, default|
            rows << [code(env), t("env_#{constant.downcase}"), default.to_s, t('not_required')]
          end
          rows
        end

        # @return [Array<String>] замечания после таблицы ENV
        def env_notes
          [production_note, t('env_secrets', keys: codes(all_credential_keys))]
        end

        private

        def authorization
          parts[:authorization]
        end

        def type_line(auth)
          t('auth_type', type: authorization.type, scheme: auth.scheme_name,
                         entry: ctx.rules.auth.name_of(authorization.entry))
        end

        def where_line
          key = authorization.query? ? 'auth_where_query' : 'auth_where_header'
          t(key, names: codes(authorization.param_names))
        end

        def stub_line
          stub = authorization.stub_name
          return nil if stub.nil?

          what = t("auth_stub_#{authorization.type}", token_url: profile.auth.token_url.to_s)
          t('auth_stub', what: what, stub: code(stub))
        end

        def signature_row
          key = parts[:signature].value(:secret_key)
          [code("provider.credentials[:#{key}]"), code('verify_signature!'), t('cred_signature')]
        end

        def all_credential_keys
          parts[:view].credential_keys
        end

        def base_url_default
          server = ctx.default_server
          return t('env_default_placeholder', url: ctx.sandbox_url) if server.nil?

          key = server.sandbox? ? 'env_default_sandbox' : 'env_default_first'
          t(key, url: server.url)
        end

        def production_note
          production = profile.servers.find(&:production?)
          return t('env_no_production') if production.nil?

          t('env_production', env: ctx.base_url_env, url: production.url)
        end
      end
    end
  end
end
