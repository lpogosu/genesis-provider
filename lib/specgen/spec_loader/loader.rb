# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Дирижирует стадией загрузки: чтение → определение версии → применение
    # OpenAPI Overlay → проверка структуры → разрешение `$ref`.
    #
    # Overlay стоит между чтением и проверкой, то есть до разрешения `$ref`:
    # его цели адресуют спецификацию так, как она написана, и
    # `$.components.schemas.X` обязана быть единственным местом, а не одной
    # из копий, разложенных резолвером по местам использования. Проверка
    # структуры идёт после overlay намеренно: она — контракт загрузчика с
    # остальным конвейером, и проверять она обязана тот документ, который
    # конвейер увидит. Иначе overlay, дописавший схему с опечаткой в `type`,
    # прошёл бы мимо неё прямо в анализаторы.
    class Loader
      # @param path [String] файл спецификации
      # @param overlay [String, nil] файл OpenAPI Overlay с переопределениями
      def initialize(path, overlay: nil)
        @path = path
        @overlay = overlay
      end

      # @return [Document]
      # @raise [SpecLoadError, SpecParseError, OverlayError]
      def load
        raw = Reader.read(@path)
        version = VersionDetector.call(raw, file: @path)
        applied = @overlay && Overlay.apply(raw, file: @overlay)
        StructureValidator.call(raw, file: @path)
        resolver = RefResolver.new(raw, file: @path)
        data = resolver.resolve
        Document.new(file: @path, version: version.version, family: version.family,
                     raw: raw, data: data, external_files: resolver.external_files,
                     overlay: applied)
      end
    end
  end
end
