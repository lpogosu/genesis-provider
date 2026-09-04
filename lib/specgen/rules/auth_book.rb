# frozen_string_literal: true

module SpecGen
  module Rules
    # OpenAPI `securitySchemes` to the credentials the generated service
    # reads and the headers it sends.
    #
    # A scheme is recognised by its `match` block (type, in, scheme, flow),
    # and the code fragments it produces are data too: the templates render
    # what the dictionary says, so adding a provider that authenticates
    # differently is a new entry here rather than a branch in a template.
    # Fragments name credentials, never values - secrets are read through
    # provider.credentials at runtime.
    class AuthBook < Book
      FILE = 'auth.yml'
      MATCH_KEYS = %w[type in scheme flow].freeze
      # A fragment key spelled with this token takes its name from the spec.
      PARAM_NAME = '%{param_name}'

      # @param name [String] entry name in the dictionary
      # @return [Hash, nil] :match, :ir_type, :location, :credential_keys,
      #   :headers, :query, :token_url_required
      def scheme(name)
        @schemes[name.to_s]
      end

      # @return [Array<String>] entry names, in dictionary order
      def names
        @schemes.keys
      end

      # @param entry [Hash] an entry #scheme_for returned
      # @return [String, nil] the name that entry is filed under
      def name_of(entry)
        @schemes.key(entry)
      end

      # Name of the header or query parameter that carries the credential.
      # A literal fragment key is the name itself (Authorization); a key
      # spelled with PARAM_NAME means the provider chose the name and the
      # spec supplies it (apiKey `name`).
      # @param entry [Hash] an entry #scheme_for returned
      # @param declaration [Hash] the securityScheme as the spec wrote it
      # @return [String, nil]
      def param_name_for(entry, declaration)
        return fragment_keys(entry).first unless spec_names_param?(entry)

        name = declaration.is_a?(Hash) ? declaration['name'] : nil
        name.is_a?(String) && !name.strip.empty? ? name : nil
      end

      # @param entry [Hash] an entry #scheme_for returned
      # @return [Boolean] the parameter name comes from the spec, not from here
      def spec_names_param?(entry)
        fragment_keys(entry).any? { |key| key.include?(PARAM_NAME) }
      end

      # Finds the entry that describes a declared security scheme.
      # @param declaration [Hash] one value of components.securitySchemes
      # @param flow [String, nil] OAuth2 flow, when the caller picked one
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
        complain('no security scheme is described', path('schemes')) if @schemes.empty?
        @schemes.freeze
      end

      def add(name, body)
        at = path('schemes', name)
        entry = compile(mapping(body, "scheme #{name}", at), at)
        check_credentials(entry, at)
        @schemes[name.to_s] = entry.freeze
      end

      def compile(fields, at)
        {
          match: match_of(fields['match'], "#{at}.match"),
          ir_type: symbol_in(fields['ir_type'], IR::Auth::TYPES, 'auth type', "#{at}.ir_type"),
          location: location_of(fields['location'], "#{at}.location"),
          credential_keys: string_list(fields['credential_keys'], 'credential keys',
                                       "#{at}.credential_keys"),
          headers: fragments(fields['headers'], "#{at}.headers"),
          query: fragments(fields['query'], "#{at}.query"),
          token_url_required: fields['requires_token_url'] == true
        }
      end

      def match_of(value, at)
        match = mapping(value, 'match block', at)
        unknown = match.keys - MATCH_KEYS
        report_unknown(unknown, at)
        complain('match must name at least the scheme type', at) if match.empty?
        match.slice(*MATCH_KEYS).transform_values { |item| item.to_s.downcase }
      end

      def report_unknown(unknown, at)
        return if unknown.empty?

        complain("match cannot key on #{unknown.join(', ')} " \
                 "(allowed: #{MATCH_KEYS.join(', ')})", at)
      end

      def location_of(value, at)
        return nil if value.nil?

        symbol_in(value, IR::Auth::LOCATIONS, 'auth location', at)
      end

      def fragments(value, at)
        mapping(value, 'code fragments', at, required: false).to_h do |key, expression|
          [key.to_s, text(expression, "fragment #{key}", "#{at}#{SpecLoader::JsonPath.segment(key)}")]
        end
      end

      def check_credentials(entry, at)
        used = (entry[:headers].values + entry[:query].values).compact
        return if used.empty?

        unused = entry[:credential_keys].reject { |key| used.any? { |line| line.include?(key) } }
        return if unused.empty?

        complain("credential keys no fragment reads: #{unused.join(', ')}", at)
      end
    end
  end
end
