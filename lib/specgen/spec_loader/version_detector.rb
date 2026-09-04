# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Determines which flavour of OpenAPI a document is written in. Only 3.x
    # is accepted: 3.0 restricts JSON Schema keywords, 3.1 and later use JSON
    # Schema 2020-12 (dependentRequired, if/then/else natively). Swagger 2.0
    # and anything else is rejected with a hint on what to do.
    class VersionDetector
      Result = Struct.new(:version, :family, keyword_init: true)

      FAMILIES = { '3.0' => :oas30, '3.1' => :oas31, '3.2' => :oas31 }.freeze
      MAJOR_MINOR = /\A(\d+\.\d+)(?:\.\d+)?\z/
      SUPPORTED = 'supported: 3.0.x, 3.1.x, 3.2.x'

      # @param data [Hash] parsed document
      # @param file [String] for error messages
      # @return [Result] version string and family (:oas30 | :oas31)
      # @raise [SpecLoadError]
      def self.call(data, file:)
        new(data, file).call
      end

      # @param data [Hash]
      # @param file [String]
      def initialize(data, file)
        @data = data
        @file = file
      end

      # @return [Result]
      def call
        reject_swagger if @data.key?('swagger')
        reject_not_openapi unless @data.key?('openapi')

        version = @data['openapi'].to_s
        family = FAMILIES[version[MAJOR_MINOR, 1]]
        unless family
          fail_load("unsupported OpenAPI version #{version.inspect}; #{SUPPORTED}",
                    '$.openapi')
        end

        Result.new(version: version, family: family)
      end

      private

      def reject_swagger
        version = @data['swagger']
        fail_load("Swagger #{version} is not supported; convert the document to OpenAPI 3 " \
                  'first (for example with swagger2openapi)', '$.swagger')
      end

      def reject_not_openapi
        keys = @data.keys.first(5).join(', ')
        fail_load("not an OpenAPI document: no `openapi` field (top-level keys: #{keys})", '$')
      end

      def fail_load(message, location)
        raise SpecLoadError.new(message, file: @file, path: location)
      end
    end
  end
end
