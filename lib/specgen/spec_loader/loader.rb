# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Дирижирует стадией загрузки: чтение → определение версии → проверка
    # структуры → разрешение `$ref`. OpenAPI Overlay, когда появится стадия
    # OverlayApplier, применяется к исходному документу между чтением и
    # проверкой: так его цели JSONPath адресуют спецификацию в том виде, в
    # котором она написана.
    class Loader
      # @param path [String] файл спецификации
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
