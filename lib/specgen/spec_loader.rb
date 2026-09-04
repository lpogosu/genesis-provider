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
  # First pipeline stage. Turns a YAML or JSON file into a Document with a
  # known OpenAPI version and every `$ref` resolved. Any bad input becomes a
  # SpecLoadError (file level) or SpecParseError (structure level) that names
  # the file and the location of the problem; the caller never sees a stack
  # trace or a Psych/JSON exception.
  module SpecLoader
    # @param path [String] path to the spec file
    # @return [Document]
    # @raise [SpecLoadError, SpecParseError]
    def self.load(path)
      Loader.new(path).load
    end
  end
end
