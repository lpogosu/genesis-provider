# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Result of loading a spec: the normalized source document (`raw`, the
    # target for an OpenAPI Overlay), the fully resolved copy the analyzers
    # read (`data`), and what is known about the file itself.
    class Document
      # @return [String] path as given on the command line
      attr_reader :file
      # @return [String] OpenAPI version string, e.g. "3.0.3"
      attr_reader :version
      # @return [Symbol] :oas30 or :oas31
      attr_reader :family
      # @return [Hash] source document with `$ref` intact
      attr_reader :raw
      # @return [Hash] document with every `$ref` replaced by its target
      attr_reader :data
      # @return [Array<String>] other files pulled in through `$ref`
      attr_reader :external_files

      # @param file [String]
      # @param version [String]
      # @param family [Symbol]
      # @param raw [Hash]
      # @param data [Hash]
      # @param external_files [Array<String>]
      def initialize(file:, version:, family:, raw:, data:, external_files: [])
        @file = file
        @version = version
        @family = family
        @raw = raw
        @data = data
        @external_files = external_files
      end

      # @return [Hash] resolved `paths` section
      def paths
        data['paths']
      end

      # @return [Hash] resolved `components` section, empty when absent
      def components
        data.fetch('components', {})
      end

      # @return [Hash] `info` section, empty when absent
      def info
        data.fetch('info', {})
      end

      # @return [Boolean] true for 3.1 and later (JSON Schema 2020-12)
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
