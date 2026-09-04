# frozen_string_literal: true

module SpecGen
  module IR
    # One declared response of an operation.
    #
    #   status       "201", "4XX" or "default", verbatim
    #   description  verbatim
    #   schema       name of the body schema in profile.schemas, or nil
    #   headers      declared response header names, e.g. ["Retry-After"]
    #   examples     {name => value}; a bare `example` is stored under
    #                "default"
    #   json_path    "$.paths['/x'].post.responses['201']"
    Response = Struct.new(:status, :description, :schema, :headers, :examples, :json_path,
                          keyword_init: true)

    # Checks and predicates of Response.
    class Response
      include Node

      STATUS = /\A(?:[1-5]\d{2}|[1-5]XX|default)\z/
      # Key under which a bare `example` is stored in `examples`.
      DEFAULT_EXAMPLE = 'default'

      # @param status [String]
      # @param description [String, nil]
      # @param schema [String, nil]
      # @param headers [Array<String>]
      # @param examples [Hash{String => Object}]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(status:, description: nil, schema: nil, headers: [], examples: {},
                     json_path: nil)
        unless status.is_a?(String) && status.match?(STATUS)
          raise ArgumentError,
                "response status must be \"NNN\", \"NXX\" or \"default\", got #{status.inspect}"
        end

        super
      end

      # @return [Integer, nil] numeric status, nil for ranges and default
      def code
        Integer(status, exception: false)
      end

      # @return [Boolean] 2xx
      def success?
        status.start_with?('2')
      end

      # @return [Boolean] whether a named header is declared
      def header?(name)
        headers.any? { |header| header.casecmp?(name) }
      end
    end
  end
end
