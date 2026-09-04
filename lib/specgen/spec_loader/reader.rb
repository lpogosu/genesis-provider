# frozen_string_literal: true

require 'date'
require 'json'
require 'psych'

module SpecGen
  module SpecLoader
    # Reads one YAML or JSON file into a Hash with string keys. Every way a
    # file can be unusable — missing, a directory, empty, malformed, not an
    # object at the root — becomes a SpecLoadError naming the file and, for
    # syntax errors, the line and column.
    class Reader
      YAML_CLASSES = [Date, Time].freeze
      JSON_EXTENSIONS = %w[.json].freeze
      YAML_EXTENSIONS = %w[.yaml .yml].freeze
      POSITION = /line (\d+),? column (\d+)/

      # @param path [String]
      # @return [Hash] parsed document with string keys
      # @raise [SpecLoadError]
      def self.read(path)
        new(path).read
      end

      # @param path [String]
      def initialize(path)
        @path = path
      end

      # @return [Hash]
      def read
        text = read_text
        fail_load('file is empty', '$') if text.strip.empty?

        data = parse(text)
        fail_load('file contains no document', '$') if data.nil?
        fail_load("root must be an object, got #{TypeName.of(data)}", '$') unless data.is_a?(Hash)

        normalize(data)
      end

      private

      def read_text
        File.read(@path, mode: 'r:bom|utf-8')
      rescue Errno::ENOENT
        fail_load('file not found')
      rescue Errno::EISDIR
        fail_load('path is a directory, not a file')
      rescue SystemCallError => e
        fail_load("cannot read file: #{e.message}")
      end

      def parse(text)
        json?(text) ? parse_json(text) : parse_yaml(text)
      end

      def json?(text)
        extension = File.extname(@path).downcase
        return true if JSON_EXTENSIONS.include?(extension)
        return false if YAML_EXTENSIONS.include?(extension)

        text.lstrip.start_with?('{', '[')
      end

      def parse_yaml(text)
        Psych.safe_load(text, permitted_classes: YAML_CLASSES, aliases: true, filename: @path)
      rescue Psych::SyntaxError => e
        context = e.context ? " #{e.context}" : ''
        fail_load("YAML syntax error: #{e.problem}#{context}", "line #{e.line}, column #{e.column}")
      rescue Psych::Exception => e
        fail_load("YAML error: #{e.message}")
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        detail = e.message.lines.first.to_s.strip
        position = detail.match(POSITION)
        location = position && "line #{position[1]}, column #{position[2]}"
        fail_load("JSON syntax error: #{detail}", location)
      end

      # YAML gives integer keys for unquoted response codes (200:), OpenAPI
      # wants strings; the rest of the pipeline relies on string keys only.
      def normalize(value)
        case value
        when Hash then value.to_h { |key, child| [key.to_s, normalize(child)] }
        when Array then value.map { |child| normalize(child) }
        else value
        end
      end

      def fail_load(message, location = nil)
        raise SpecLoadError.new(message, file: @path, path: location)
      end
    end
  end
end
