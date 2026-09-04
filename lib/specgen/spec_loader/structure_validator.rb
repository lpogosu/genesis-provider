# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Проверяет то, без чего конвейер работать не может: `paths` должен быть
    # непустым объектом объектов, а `type` каждой схемы — типом JSON Schema.
    # Первое нарушение становится SpecParseError с JSONPath виноватого
    # элемента.
    class StructureValidator
      TYPES = %w[string number integer boolean array object null].freeze

      # @param data [Hash] исходный документ
      # @param file [String] для сообщений об ошибках
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
        fail_parse(Texts.t('spec_loader.structure.paths_missing'), ['paths']) if paths.nil?
        unless paths.is_a?(Hash)
          fail_parse(Texts.t('spec_loader.structure.paths_type', type: TypeName.of(paths)),
                     ['paths'])
        end
        fail_parse(Texts.t('spec_loader.structure.paths_empty'), ['paths']) if paths.empty?

        validate_path_items(paths)
      end

      def validate_path_items(paths)
        paths.each do |route, item|
          next if item.is_a?(Hash)

          fail_parse(Texts.t('spec_loader.structure.path_item_type', type: TypeName.of(item)),
                     ['paths', route])
        end
      end

      def validate_schema_types
        SchemaWalker.each_schema(@data) do |schema, keys|
          Array(schema['type']).each do |type|
            next if TYPES.include?(type)

            fail_parse(unknown_type_message(type), keys + ['type'])
          end
        end
      end

      def unknown_type_message(type)
        Texts.t('spec_loader.structure.unknown_type', type: type.inspect,
                                                      types: TYPES.join(', '))
      end

      def fail_parse(message, keys)
        raise SpecParseError.new(message, file: @file, path: JsonPath.build(keys))
      end
    end
  end
end
