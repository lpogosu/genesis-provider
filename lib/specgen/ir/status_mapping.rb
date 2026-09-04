# frozen_string_literal: true

module SpecGen
  module IR
    # Provider status → internal status.
    #
    #   provider_status  verbatim, e.g. "pending"
    #   internal         Derived<Symbol> one of Roles::INTERNAL_STATUS, or
    #                    unknown when no canon or synonym matched
    #   json_path        where the status was declared, usually the enum
    StatusMapping = Struct.new(:provider_status, :internal, :json_path, keyword_init: true)

    # Checks and predicates of StatusMapping.
    class StatusMapping
      include Node

      # @param provider_status [String]
      # @param internal [Derived]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(provider_status:, internal:, json_path: nil)
        Node.assert_text!(provider_status, 'provider status')
        Node.assert_derived!(internal, 'internal status', allowed: Roles::INTERNAL_STATUS)
        super
      end

      # @return [Boolean]
      def mapped?
        internal.known?
      end
    end
  end
end
