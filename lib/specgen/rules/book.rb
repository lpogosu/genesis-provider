# frozen_string_literal: true

module SpecGen
  module Rules
    # One dictionary file under rules/. A Book checks its file against the
    # closed vocabularies of IR::Roles and the IR value objects, then exposes
    # it as the lookups analyzers and generators call. Problems go into a
    # shared collector instead of being raised, so a load reports every
    # mistake in every dictionary at once and then refuses to hand back a
    # half-valid registry.
    #
    # A subclass declares FILE and implements #build.
    class Book
      include Checks

      SUPPORTED_VERSION = 1

      # @return [String] path of the file this book was read from
      attr_reader :file

      # @param document [Document] already parsed dictionary
      # @param problems [Problems] shared collector
      def initialize(document, problems)
        @file = document.file
        @data = document.data
        @problems = problems
        check_version
        build
      end

      # @return [String] basename, the way messages name the dictionary
      def name
        File.basename(file)
      end

      private

      attr_reader :data, :problems

      # Fills the lookups from `data`. Subclasses override.
      # @return [void]
      def build; end

      def check_version
        version = data['version']
        return if version == SUPPORTED_VERSION

        complain("dictionary version must be #{SUPPORTED_VERSION}, got #{describe(version)}",
                 path('version'))
      end

      # @param key [String] name of a top-level section
      # @param type [Class] Hash or Array
      # @param required [Boolean] whether an absent section is a problem
      # @return [Hash, Array] the section, or an empty one
      def section(key, type = Hash, required: true)
        value = data[key]
        return value if value.is_a?(type)
        return type.new if value.nil? && !required

        expected = SpecLoader::TypeName::NAMES.fetch(type)
        complain("section must be an #{expected}, got #{describe(value)}", path(key))
        type.new
      end

      def path(*keys)
        SpecLoader::JsonPath.build(keys)
      end

      def complain(message, at)
        problems.add(message, file: file, path: at)
      end
    end
  end
end
