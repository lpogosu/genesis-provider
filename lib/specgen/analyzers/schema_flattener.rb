# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Folds `allOf` into one schema object and reports the composition
    # keywords we do not decompose.
    #
    # `allOf` is the common way to say "these fields plus those": losing a
    # branch loses required fields from the generated request, so branches
    # are merged - the outer schema first, then each branch in order, and a
    # property already present is kept rather than overwritten.
    #
    # `oneOf` and `anyOf` describe variants, not a sum, and turning them
    # into one flat schema would invent fields the provider never accepts
    # together. They are reported instead: the report says which variants
    # exist and that a human has to pick.
    module SchemaFlattener
      VARIANTS = %w[oneOf anyOf].freeze

      # @param node [Object] a schema object
      # @return [Array(Hash, Array<Array(Symbol, String)>)] the merged
      #   schema and [warning code, message] pairs for the caller to record
      def self.call(node)
        return [{}, []] unless node.is_a?(Hash)

        notes = []
        merged = merge(node, notes)
        VARIANTS.each { |keyword| note_variants(node, keyword, notes) }
        [merged, notes]
      end

      # @return [Hash]
      def self.merge(node, notes)
        branches = node['allOf']
        return node unless branches.is_a?(Array)

        merged = node.except('allOf')
        branches.grep(Hash).each { |branch| absorb(merged, branch, notes) }
        merged
      end

      # @return [void]
      def self.absorb(merged, branch, notes)
        merged['type'] ||= branch['type']
        merged['description'] ||= branch['description']
        merged['properties'] = merge_properties(merged, branch, notes)
        required = list(merged['required']) | list(branch['required'])
        merged['required'] = required unless required.empty?
      end

      # @return [Hash]
      def self.merge_properties(merged, branch, notes)
        properties = merged['properties'].is_a?(Hash) ? merged['properties'].dup : {}
        listed = branch['properties']
        return properties unless listed.is_a?(Hash)

        listed.each do |name, schema|
          note_conflict(properties[name], schema, name, notes)
          properties[name] ||= schema
        end
        properties
      end

      # @return [void]
      def self.note_conflict(kept, incoming, name, notes)
        return unless kept.is_a?(Hash) && incoming.is_a?(Hash)

        types = [kept['type'], incoming['type']]
        return if types.any?(&:nil?) || types.uniq.size == 1

        notes << [:spec_element_unsupported,
                  "allOf branches disagree on the type of `#{name}` " \
                  "(#{types.first} and #{types.last}); the first was kept"]
      end

      # @return [void]
      def self.note_variants(node, keyword, notes)
        branches = node[keyword]
        return unless branches.is_a?(Array) && !branches.empty?

        notes << [:spec_element_unsupported,
                  "`#{keyword}` with #{branches.size} variants is not decomposed: the fields " \
                  'of the variants are not in the IR, so a request built from this schema ' \
                  'needs a human to choose the variant']
      end

      # @return [Array<String>]
      def self.list(value)
        value.is_a?(Array) ? value.grep(String) : []
      end
    end
  end
end
