# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Checks the parts of a document the pipeline cannot work without:
    # `paths` must be a non-empty object of objects, and every schema `type`
    # must be a JSON Schema type. The first violation is reported as a
    # SpecParseError with the JSONPath of the offending element.
    class StructureValidator
      TYPES = %w[string number integer boolean array object null].freeze

      # @param data [Hash] raw document
      # @param file [String] for error messages
      # @raise [SpecParseError]
      def self.call(data, file:)
        new(data, file).call
      end

      # @param data [Hash]
      # @param file [String]
      def initialize(data, file)
        @data = data
        @file = file
      end

      # @return [void]
      def call
        validate_paths
        validate_schema_types
      end

      private

      def validate_paths
        paths = @data['paths']
        fail_parse('`paths` is missing, nothing to generate', ['paths']) if paths.nil?
        unless paths.is_a?(Hash)
          fail_parse("`paths` must be an object, got #{TypeName.of(paths)}",
                     ['paths'])
        end
        fail_parse('`paths` is empty, nothing to generate', ['paths']) if paths.empty?

        paths.each do |route, item|
          next if item.is_a?(Hash)

          fail_parse("path item must be an object, got #{TypeName.of(item)}", ['paths', route])
        end
      end

      def validate_schema_types
        SchemaWalker.each_schema(@data) do |schema, keys|
          Array(schema['type']).each do |type|
            next if TYPES.include?(type)

            fail_parse("unknown schema type #{type.inspect}; expected one of #{TYPES.join(', ')}",
                       keys + ['type'])
          end
        end
      end

      def fail_parse(message, keys)
        raise SpecParseError.new(message, file: @file, path: JsonPath.build(keys))
      end
    end
  end
end
