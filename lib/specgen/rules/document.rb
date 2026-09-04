# frozen_string_literal: true

require 'psych'

module SpecGen
  module Rules
    # Reads one dictionary file into a Hash with string keys. Everything that
    # can be wrong with the file itself — missing, unreadable, malformed,
    # empty, not an object, or carrying a key twice — becomes a RulesError
    # naming the file and, for a syntax error, the line and column.
    class Document
      # @return [String] path the dictionary was read from
      attr_reader :file
      # @return [Hash] parsed document with string keys
      attr_reader :data

      # @param path [String]
      # @return [Document]
      # @raise [RulesError]
      def self.read(path)
        new(path).read
      end

      # @param path [String]
      def initialize(path)
        @file = path
      end

      # @return [Document] self, with `data` filled in
      # @raise [RulesError]
      def read
        text = read_text
        reject_duplicates(text)
        @data = parse(text)
        return self if @data.is_a?(Hash) && !@data.empty?

        fail_rules("dictionary must be a non-empty object, got #{SpecLoader::TypeName.of(@data)}",
                   '$')
      end

      private

      def read_text
        File.read(file, mode: 'r:bom|utf-8')
      rescue Errno::ENOENT
        fail_rules('dictionary not found')
      rescue Errno::EISDIR
        fail_rules('path is a directory, not a file')
      rescue SystemCallError => e
        fail_rules("cannot read dictionary: #{e.message}")
      end

      def parse(text)
        Psych.safe_load(text, aliases: true, filename: file)
      rescue Psych::SyntaxError => e
        fail_rules("YAML syntax error: #{e.problem}", "line #{e.line}, column #{e.column}")
      rescue Psych::Exception => e
        fail_rules("YAML error: #{e.message}")
      end

      def reject_duplicates(text)
        duplicates = DuplicateKeys.find(text, file)
        return if duplicates.empty?

        listed = duplicates.map { |path, line| "#{path} (line #{line})" }.join(', ')
        fail_rules("declared more than once: #{listed}; YAML silently keeps the last value")
      rescue Psych::SyntaxError => e
        fail_rules("YAML syntax error: #{e.problem}", "line #{e.line}, column #{e.column}")
      end

      def fail_rules(message, location = nil)
        raise RulesError.new(message, file: file, path: location)
      end
    end
  end
end
