# frozen_string_literal: true

require 'psych'

module SpecGen
  module Rules
    # Finds keys declared twice inside the same YAML mapping. Psych keeps the
    # last value and says nothing, so a synonym pasted under two roles or a
    # currency listed twice with different exponents would load cleanly and
    # behave wrongly. In a hand-curated dictionary that is always a mistake,
    # so the loader refuses the file instead of guessing which one was meant.
    module DuplicateKeys
      # @param text [String] YAML source
      # @param file [String] path, used in the parser's own messages
      # @return [Array<Array(String, Integer)>] JSONPath and line of each
      #   repeated key, in document order
      # @raise [Psych::SyntaxError] when the file does not parse at all
      def self.find(text, file)
        document = Psych.parse(text, filename: file)
        return [] unless document

        found = []
        walk(document.root, [], found)
        found
      end

      # @param node [Psych::Nodes::Node, nil]
      # @param keys [Array<String, Integer>] path from the document root
      # @param found [Array] accumulator
      # @return [void]
      def self.walk(node, keys, found)
        case node
        when Psych::Nodes::Mapping then walk_mapping(node, keys, found)
        when Psych::Nodes::Sequence
          node.children.each_with_index { |child, index| walk(child, keys + [index], found) }
        end
      end

      # @return [void]
      def self.walk_mapping(node, keys, found)
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          key = key_node.is_a?(Psych::Nodes::Scalar) ? key_node.value : nil
          next if key.nil?

          found << [SpecLoader::JsonPath.build(keys + [key]), key_node.start_line + 1] if seen[key]
          seen[key] = true
          walk(value_node, keys + [key], found)
        end
      end
    end
  end
end
