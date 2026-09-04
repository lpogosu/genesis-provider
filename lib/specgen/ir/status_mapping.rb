# frozen_string_literal: true

module SpecGen
  module IR
    # Статус провайдера → внутренний статус.
    #
    #   provider_status  дословно, например "pending"
    #   internal         Derived<Symbol>, один из Roles::INTERNAL_STATUS,
    #                    либо не выведено, если не совпал ни канон, ни синоним
    #   json_path        где статус объявлен, обычно enum
    StatusMapping = Struct.new(:provider_status, :internal, :json_path, keyword_init: true)

    # Проверки и предикаты StatusMapping.
    class StatusMapping
      include Node

      # @param provider_status [String]
      # @param internal [Derived]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(provider_status:, internal:, json_path: nil)
        Node.assert_text!(provider_status, 'статус провайдера')
        Node.assert_derived!(internal, 'внутренний статус', allowed: Roles::INTERNAL_STATUS)
        super
      end

      # @return [Boolean]
      def mapped?
        internal.known?
      end
    end
  end
end
