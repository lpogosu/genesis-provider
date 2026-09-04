# frozen_string_literal: true

module SpecGen
  module IR
    # Как авторизуются исходящие запросы. Один на профиль: если спецификация
    # объявляет несколько схем авторизации, анализатор выбирает ту, которую
    # действительно требуют операции, и предупреждает об остальных.
    #
    #   scheme_name      ключ внутри components.securitySchemes
    #   type             Derived<Symbol>, один из TYPES
    #   location         :header | :query | :cookie; nil, если не применимо
    #   param_name       имя заголовка или query-параметра, дословно
    #   credential_keys  Derived<Array<String>> — ключи, которые
    #                    сгенерированный сервис читает из
    #                    provider.credentials, например ["api_key"]
    #   token_url        эндпоинт токена OAuth2, иначе nil
    #   scopes           scopes OAuth2, иначе []
    #   json_path        "$.components.securitySchemes.X"
    Auth = Struct.new(:scheme_name, :type, :location, :param_name, :credential_keys,
                      :token_url, :scopes, :json_path, keyword_init: true)

    # Словарь значений и проверки Auth.
    class Auth
      include Node

      TYPES = %i[api_key bearer basic oauth2 hmac none].freeze
      LOCATIONS = %i[header query cookie].freeze

      # @param type [Derived]
      # @param scheme_name [String, nil]
      # @param location [Symbol, nil] одно из LOCATIONS
      # @param param_name [String, nil]
      # @param credential_keys [Derived, nil]
      # @param token_url [String, nil]
      # @param scopes [Array<String>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(type:, scheme_name: nil, location: nil, param_name: nil, credential_keys: nil,
                     token_url: nil, scopes: [], json_path: nil)
        Node.assert_derived!(type, 'тип авторизации', allowed: TYPES)
        Node.assert_member!(LOCATIONS, location, 'место учётных данных') unless location.nil?
        Node.assert_derived!(credential_keys, 'ключи credentials') unless credential_keys.nil?
        super
      end

      # @return [Boolean] запросы не несут учётных данных вообще
      def none?
        type.value == :none
      end
    end
  end
end
