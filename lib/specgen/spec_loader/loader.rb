# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Orchestrates the loading stage: read → detect version → validate
    # structure → resolve `$ref`. An OpenAPI Overlay, when the OverlayApplier
    # stage exists, is applied to the raw document between reading and
    # validation, so its JSONPath targets address the source as written.
    class Loader
      # @param path [String] spec file
      def initialize(path)
        @path = path
      end

      # @return [Document]
      # @raise [SpecLoadError, SpecParseError]
      def load
        raw = Reader.read(@path)
        version = VersionDetector.call(raw, file: @path)
        StructureValidator.call(raw, file: @path)
        resolver = RefResolver.new(raw, file: @path)
        data = resolver.resolve
        Document.new(file: @path, version: version.version, family: version.family,
                     raw: raw, data: data, external_files: resolver.external_files)
      end
    end
  end
end
