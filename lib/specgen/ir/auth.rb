# frozen_string_literal: true

module SpecGen
  module IR
    # How outgoing requests authenticate. One per profile: when a spec
    # declares several security schemes the analyzer picks the one the
    # operations actually require and warns about the rest.
    #
    #   scheme_name      key under components.securitySchemes
    #   type             Derived<Symbol> one of TYPES
    #   location         :header | :query | :cookie, nil when not applicable
    #   param_name       header or query parameter name, verbatim
    #   credential_keys  Derived<Array<String>> keys the generated service
    #                    reads from provider.credentials, e.g. ["api_key"]
    #   token_url        OAuth2 token endpoint, else nil
    #   scopes           OAuth2 scopes, else []
    #   json_path        "$.components.securitySchemes.X"
    Auth = Struct.new(:scheme_name, :type, :location, :param_name, :credential_keys,
                      :token_url, :scopes, :json_path, keyword_init: true)

    # Vocabulary and checks of Auth.
    class Auth
      include Node

      TYPES = %i[api_key bearer basic oauth2 hmac none].freeze
      LOCATIONS = %i[header query cookie].freeze

      # @param type [Derived]
      # @param scheme_name [String, nil]
      # @param location [Symbol, nil] one of LOCATIONS
      # @param param_name [String, nil]
      # @param credential_keys [Derived, nil]
      # @param token_url [String, nil]
      # @param scopes [Array<String>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(type:, scheme_name: nil, location: nil, param_name: nil, credential_keys: nil,
                     token_url: nil, scopes: [], json_path: nil)
        Node.assert_derived!(type, 'auth type', allowed: TYPES)
        Node.assert_member!(LOCATIONS, location, 'auth location') unless location.nil?
        Node.assert_derived!(credential_keys, 'credential keys') unless credential_keys.nil?
        super
      end

      # @return [Boolean] requests carry no credentials at all
      def none?
        type.value == :none
      end
    end
  end
end
