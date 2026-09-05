# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Результат загрузки спецификации: нормализованный исходный документ
    # (`raw` — цель для OpenAPI Overlay), полностью разрешённая копия,
    # которую читают анализаторы (`data`), и то, что известно про сам файл.
    class Document
      # @return [String] путь, как он задан в командной строке
      attr_reader :file
      # @return [String] строка версии OpenAPI, например "3.0.3"
      attr_reader :version
      # @return [Symbol] :oas30 или :oas31
      attr_reader :family
      # @return [Hash] исходный документ с нетронутыми `$ref`
      attr_reader :raw
      # @return [Hash] документ, в котором каждый `$ref` заменён своей целью
      attr_reader :data
      # @return [Array<String>] другие файлы, подтянутые через `$ref`
      attr_reader :external_files
      # @return [Overlay::Result, nil] что сделал с документом файл overlay;
      #   nil, если флаг --overlay не указывали
      attr_reader :overlay

      # @param file [String]
      # @param version [String]
      # @param family [Symbol]
      # @param raw [Hash]
      # @param data [Hash]
      # @param external_files [Array<String>]
      # @param overlay [Overlay::Result, nil]
      def initialize(file:, version:, family:, raw:, data:, external_files: [], overlay: nil)
        @file = file
        @version = version
        @family = family
        @raw = raw
        @data = data
        @external_files = external_files
        @overlay = overlay
      end

      # @return [Hash] разрешённая секция `paths`
      def paths
        data['paths']
      end

      # @return [Hash] разрешённая секция `components`, пустая при отсутствии
      def components
        data.fetch('components', {})
      end

      # @return [Hash] секция `info`, пустая при отсутствии
      def info
        data.fetch('info', {})
      end

      # @return [Boolean] true для 3.1 и выше (JSON Schema 2020-12)
      def oas31?
        family == :oas31
      end

      # @return [String]
      def to_s
        "#{file} (OpenAPI #{version})"
      end
    end
  end
end
