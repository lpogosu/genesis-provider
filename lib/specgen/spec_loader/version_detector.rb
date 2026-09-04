# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Определяет, на каком диалекте OpenAPI написан документ. Принимаем
    # только 3.x: в 3.0 часть ключевых слов JSON Schema запрещена, а 3.1 и
    # выше используют JSON Schema 2020-12 (`dependentRequired`, if/then/else
    # нативно). Swagger 2.0 и всё остальное отклоняем с подсказкой, что
    # делать дальше.
    class VersionDetector
      Result = Struct.new(:version, :family, keyword_init: true)

      FAMILIES = { '3.0' => :oas30, '3.1' => :oas31, '3.2' => :oas31 }.freeze
      MAJOR_MINOR = /\A(\d+\.\d+)(?:\.\d+)?\z/
      SUPPORTED = '3.0.x, 3.1.x, 3.2.x'

      # @param data [Hash] разобранный документ
      # @param file [String] для сообщений об ошибках
      # @return [Result] строка версии и семейство (:oas30 | :oas31)
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
        reject_version(version) unless family

        Result.new(version: version, family: family)
      end

      private

      def reject_swagger
        fail_load(Texts.t('spec_loader.version.swagger', version: @data['swagger']),
                  '$.swagger')
      end

      def reject_version(version)
        fail_load(Texts.t('spec_loader.version.unsupported', version: version.inspect,
                                                             supported: SUPPORTED),
                  '$.openapi')
      end

      def reject_not_openapi
        keys = @data.keys.first(5).join(', ')
        fail_load(Texts.t('spec_loader.version.not_openapi', keys: keys), '$')
      end

      def fail_load(message, location)
        raise SpecLoadError.new(message, file: @file, path: location)
      end
    end
  end
end
