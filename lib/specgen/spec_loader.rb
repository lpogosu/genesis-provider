# frozen_string_literal: true

require_relative 'spec_loader/type_name'
require_relative 'spec_loader/json_path'
require_relative 'spec_loader/json_pointer'
require_relative 'spec_loader/reader'
require_relative 'spec_loader/version_detector'
require_relative 'spec_loader/schema_walker'
require_relative 'spec_loader/structure_validator'
require_relative 'spec_loader/ref_resolver'
require_relative 'spec_loader/document'
require_relative 'spec_loader/loader'

module SpecGen
  # Первая стадия конвейера. Превращает файл YAML или JSON в Document с
  # известной версией OpenAPI и разрешёнными `$ref`. Любой плохой ввод
  # становится SpecLoadError (уровень файла) или SpecParseError (уровень
  # структуры), которая называет файл и место проблемы; вызывающий никогда
  # не видит ни стектрейса, ни исключения из Psych или JSON.
  module SpecLoader
    # @param path [String] путь к файлу спецификации
    # @return [Document]
    # @raise [SpecLoadError, SpecParseError]
    def self.load(path)
      Loader.new(path).load
    end
  end
end
