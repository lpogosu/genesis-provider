# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Заголовки авторизации по profile.auth и rules/auth.yml: имя
      # заголовка из спецификации, выражение — из справочника, секрет —
      # только через provider.credentials. OAuth2 и HMAC запроса требуют
      # кода, которого спецификация не описывает, — для них генерируются
      # методы-заглушки с TODO.
      class Authorization
        INDENT = 6
        PARAM_NAME = Rules::AuthBook::PARAM_NAME
        CREDENTIALS = 'provider.credentials'
        # Заглушки по типу авторизации: имя метода, параметры, ключ текста.
        STUBS = { oauth2: ['access_token', %w[client_id client_secret], 'oauth2_stub'],
                  hmac: ['request_signature', %w[body secret], 'hmac_stub'] }.freeze

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @auth = ctx.profile.auth
          @entry = ctx.auth_scheme
        end

        # @return [Array<Method>] auth_headers и, если нужны, auth_query и
        #   заглушка получения токена или подписи запроса
        def methods
          list = [Method.new(name: @ctx.helper(:auth_headers), params: [], doc: doc,
                             body: headers_body)]
          list << query_method if query?
          list << stub(*STUBS[type]) if STUBS.key?(type)
          list
        end

        # @return [Boolean] учётные данные уходят в строку запроса
        def query?
          @entry&.dig(:location) == :query
        end

        # @return [Symbol, nil] тип авторизации из IR::Auth::TYPES
        def type
          @auth&.type&.value
        end

        # @return [Hash, nil] запись rules/auth.yml, по которой собраны
        #   заголовки; nil, если схема не распознана или её нет
        attr_reader :entry

        # @return [Boolean] авторизация объявлена и узнана справочником
        def recognised?
          !(@auth.nil? || @auth.none? || @entry.nil?)
        end

        # @return [Array<String>] имена заголовков или query-параметров, в
        #   которых уходят учётные данные, уже с именем из спецификации
        def param_names
          return [] unless recognised?

          fragments = query? ? @entry[:query] : @entry[:headers]
          fragments.keys.map { |name| name.gsub(PARAM_NAME, @auth.param_name.to_s) }
        end

        # @return [Array<String>] ключи provider.credentials, которые читает
        #   сервис: из IR, иначе из записи справочника
        def credential_keys
          keys = @auth&.credential_keys
          return keys.value if keys&.known?

          recognised? ? @entry[:credential_keys] : []
        end

        # @return [String, nil] имя метода-заглушки для этого типа (получение
        #   токена или подпись запроса), если она генерируется
        def stub_name
          STUBS.dig(type, 0)
        end

        private

        def doc
          Ruby.comment(doc_text, width: Ruby::WIDTH - 4) + ['# @return [Hash]']
        end

        def doc_text
          return @ctx.t('auth_none') if @auth.nil? || @auth.none?
          return @ctx.t('auth_unknown', scheme: @auth.scheme_name) if @entry.nil?

          @ctx.t('auth_doc', scheme: @auth.scheme_name, type: type,
                             entry: @ctx.rules.auth.name_of(@entry))
        end

        def headers_body
          return ['{}'] if @auth.nil? || @auth.none?
          return todo('auth_todo') + ['{}'] if @entry.nil?
          return note('auth_query_note') + ['{}'] if query?

          hash_lines(@entry[:headers])
        end

        def query_method
          Method.new(name: 'auth_query', params: [],
                     doc: note('auth_query_doc', width: 4) + ['# @return [Hash]'],
                     body: hash_lines(@entry[:query]))
        end

        # Хеш «имя → выражение» из фрагментов справочника; %{param_name}
        # заменяется именем из спецификации. Слишком длинная запись получает
        # локальную переменную credentials и перенос значения на свою строку.
        def hash_lines(fragments)
          pairs = fragments.map do |name, expression|
            [Ruby.str(name.gsub(PARAM_NAME, @auth.param_name.to_s)), expression]
          end
          return ['{}'] if pairs.empty?

          single = "{ #{pairs.first.first} => #{pairs.first.last} }"
          return [single] if pairs.one? && fits?(single, INDENT)

          shorten(pairs) + ['{', *entries(pairs), '}']
        end

        def shorten(pairs)
          return [] if pairs.all? { |name, expression| fits?("#{name} => #{expression},", 8) }

          pairs.each { |pair| pair[1] = pair[1].gsub(CREDENTIALS, 'credentials') }
          ["credentials = #{CREDENTIALS}"]
        end

        def entries(pairs)
          pairs.each_with_index.flat_map do |(name, expression), index|
            comma = index == pairs.size - 1 ? '' : ','
            line = "#{name} => #{expression}#{comma}"
            fits?(line, 8) ? ["  #{line}"] : ["  #{name} =>", "    #{expression}#{comma}"]
          end
        end

        def fits?(line, indent)
          indent + line.size <= Ruby::WIDTH
        end

        def stub(name, params, key)
          message = Ruby.str(@ctx.t("#{key}_message"))
          Method.new(name: name, params: params.map { |param| { name: param } },
                     doc: note(key, width: 4),
                     body: todo(key) + ["raise NotImplementedError, #{message}"])
        end

        def note(key, width: INDENT, prefix: '# ')
          text = @ctx.t(key, token_url: @auth&.token_url.to_s)
          Ruby.comment(text, width: Ruby::WIDTH - width, prefix: prefix)
        end

        def todo(key)
          note(key, prefix: '# TODO: ')
        end
      end
    end
  end
end
