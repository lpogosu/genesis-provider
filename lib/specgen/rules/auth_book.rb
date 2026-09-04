# frozen_string_literal: true

module SpecGen
  module Rules
    # `securitySchemes` OpenAPI → учётные данные, которые читает
    # сгенерированный сервис, и заголовки, которые он отправляет.
    #
    # Схема распознаётся своим блоком `match` (type, in, scheme, flow), а
    # фрагменты кода, которые она даёт, — тоже данные: шаблоны выводят то,
    # что сказано в справочнике, поэтому провайдер с другой авторизацией —
    # это новая запись здесь, а не ветка в шаблоне. Фрагменты называют
    # учётные данные, но никогда не значения: секреты читаются в рантайме
    # через provider.credentials.
    class AuthBook < Book
      FILE = 'auth.yml'
      MATCH_KEYS = %w[type in scheme flow].freeze
      # Ключ фрагмента с этим токеном берёт имя из спецификации.
      PARAM_NAME = '%{param_name}'

      # @param name [String] имя записи в справочнике
      # @return [Hash, nil] :match, :ir_type, :location, :credential_keys,
      #   :headers, :query, :token_url_required
      def scheme(name)
        @schemes[name.to_s]
      end

      # @return [Array<String>] имена записей, в порядке справочника
      def names
        @schemes.keys
      end

      # @param entry [Hash] запись, которую вернул #scheme_for
      # @return [String, nil] имя, под которым эта запись лежит
      def name_of(entry)
        @schemes.key(entry)
      end

      # Имя заголовка или query-параметра, который несёт учётные данные.
      # Буквальный ключ фрагмента и есть само имя (Authorization); ключ,
      # написанный через PARAM_NAME, означает, что имя выбрал провайдер и его
      # даёт спецификация (`name` у apiKey).
      # @param entry [Hash] запись, которую вернул #scheme_for
      # @param declaration [Hash] securityScheme, как его написала спецификация
      # @return [String, nil]
      def param_name_for(entry, declaration)
        return fragment_keys(entry).first unless spec_names_param?(entry)

        name = declaration.is_a?(Hash) ? declaration['name'] : nil
        name.is_a?(String) && !name.strip.empty? ? name : nil
      end

      # @param entry [Hash] запись, которую вернул #scheme_for
      # @return [Boolean] имя параметра приходит из спецификации, а не отсюда
      def spec_names_param?(entry)
        fragment_keys(entry).any? { |key| key.include?(PARAM_NAME) }
      end

      # Находит запись, описывающую объявленную схему авторизации.
      # @param declaration [Hash] одно значение components.securitySchemes
      # @param flow [String, nil] flow OAuth2, если вызывающий выбрал один
      # @return [Hash, nil]
      def scheme_for(declaration, flow: nil)
        facts = facts_of(declaration, flow)
        @schemes.values.find { |entry| entry[:match].all? { |key, value| facts[key] == value } }
      end

      private

      def fragment_keys(entry)
        entry[:headers].keys + entry[:query].keys
      end

      def facts_of(declaration, flow)
        flows = declaration['flows']
        {
          'type' => declaration['type'], 'in' => declaration['in'],
          'scheme' => declaration['scheme'],
          'flow' => flow || (flows.is_a?(Hash) ? flows.keys.first : nil)
        }.compact.transform_values { |value| value.to_s.downcase }
      end

      def build
        @schemes = {}
        section('schemes').each { |name, body| add(name, body) }
        fault('auth.empty', path('schemes')) if @schemes.empty?
        @schemes.freeze
      end

      def add(name, body)
        at = path('schemes', name)
        entry = compile(mapping(body, noun(:scheme_body, name: name), at), at)
        check_credentials(entry, at)
        @schemes[name.to_s] = entry.freeze
      end

      def compile(fields, at)
        {
          match: match_of(fields['match'], "#{at}.match"),
          ir_type: symbol_in(fields['ir_type'], IR::Auth::TYPES, noun(:auth_type),
                             "#{at}.ir_type"),
          location: location_of(fields['location'], "#{at}.location"),
          credential_keys: string_list(fields['credential_keys'], noun(:credential_keys),
                                       "#{at}.credential_keys"),
          headers: fragments(fields['headers'], "#{at}.headers"),
          query: fragments(fields['query'], "#{at}.query"),
          token_url_required: fields['requires_token_url'] == true
        }
      end

      def match_of(value, at)
        match = mapping(value, noun(:match_block), at)
        report_unknown(match.keys - MATCH_KEYS, at)
        fault('auth.match_empty', at) if match.empty?
        match.slice(*MATCH_KEYS).transform_values { |item| item.to_s.downcase }
      end

      def report_unknown(unknown, at)
        return if unknown.empty?

        fault('auth.unknown_match_key', at, keys: unknown.join(', '),
                                            allowed: MATCH_KEYS.join(', '))
      end

      def location_of(value, at)
        return nil if value.nil?

        symbol_in(value, IR::Auth::LOCATIONS, noun(:auth_location), at)
      end

      def fragments(value, at)
        mapping(value, noun(:fragments), at, required: false).to_h do |key, expression|
          [key.to_s, text(expression, noun(:fragment, key: key),
                          "#{at}#{SpecLoader::JsonPath.segment(key)}")]
        end
      end

      def check_credentials(entry, at)
        used = (entry[:headers].values + entry[:query].values).compact
        return if used.empty?

        unused = entry[:credential_keys].reject { |key| used.any? { |line| line.include?(key) } }
        return if unused.empty?

        fault('auth.unused_credentials', at, keys: unused.join(', '))
      end
    end
  end
end
