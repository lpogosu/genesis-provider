# frozen_string_literal: true

module SpecGen
  module IR
    # Одна запись списка `servers` из спецификации.
    #
    #   url          дословно
    #   environment  Derived<Symbol> :sandbox | :production; не выведено,
    #                если ни описание, ни хост не говорят, что это за среда
    #   description  дословно
    #   json_path    "$.servers[0]"
    Server = Struct.new(:url, :environment, :description, :json_path, keyword_init: true)

    # Словарь значений и проверки Server.
    class Server
      include Node

      ENVIRONMENTS = %i[sandbox production].freeze

      # @param url [String]
      # @param environment [Derived]
      # @param description [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(url:, environment:, description: nil, json_path: nil)
        Node.assert_text!(url, 'URL сервера')
        Node.assert_derived!(environment, 'среда сервера', allowed: ENVIRONMENTS)
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
