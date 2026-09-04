# frozen_string_literal: true

module SpecGen
  module IR
    # One entry of the spec's `servers` list.
    #
    #   url          verbatim
    #   environment  Derived<Symbol> :sandbox | :production; unknown when
    #                neither description nor host says which it is
    #   description  verbatim
    #   json_path    "$.servers[0]"
    Server = Struct.new(:url, :environment, :description, :json_path, keyword_init: true)

    # Vocabulary and checks of Server.
    class Server
      include Node

      ENVIRONMENTS = %i[sandbox production].freeze

      # @param url [String]
      # @param environment [Derived]
      # @param description [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(url:, environment:, description: nil, json_path: nil)
        Node.assert_text!(url, 'server url')
        Node.assert_derived!(environment, 'server environment', allowed: ENVIRONMENTS)
        super
      end

      # @return [Boolean]
      def sandbox?
        environment.value == :sandbox
      end

      # @return [Boolean]
      def production?
        environment.value == :production
      end
    end
  end
end
