# frozen_string_literal: true

module SpecGen
  module Analyzers
    # JSON Schema validation keywords, as IR::Field stores them.
    #
    # Two spellings have to end up as one thing, because the generated
    # service must not care which dialect the provider wrote in:
    #
    #   nullable   OAS 3.0 writes `nullable: true`; JSON Schema 2020-12
    #              (OAS 3.1) writes `type: ["string", "null"]`
    #   exclusive  OAS 3.0 writes `exclusiveMinimum: true` as a modifier of
    #              `minimum`; 2020-12 writes `exclusiveMinimum: 100` on its
    #              own. Both are stored the 2020-12 way - as a number - so a
    #              template renders one comparison instead of two.
    module ConstraintReader
      # Keyword in the spec => key in IR::Field::CONSTRAINT_KEYS.
      KEYS = {
        'enum' => :enum, 'const' => :const, 'pattern' => :pattern, 'minimum' => :minimum,
        'maximum' => :maximum, 'minLength' => :min_length, 'maxLength' => :max_length,
        'minItems' => :min_items, 'maxItems' => :max_items, 'multipleOf' => :multiple_of,
        'default' => :default
      }.freeze
      # Keyword => [constraint it sets, constraint it replaces when boolean].
      EXCLUSIVE = {
        'exclusiveMinimum' => %i[exclusive_minimum minimum],
        'exclusiveMaximum' => %i[exclusive_maximum maximum]
      }.freeze
      NULL = 'null'

      # @param node [Hash] a schema object
      # @return [Array(String, Boolean)] the type as the IR keeps it, and
      #   whether null is allowed
      def self.type_of(node)
        declared = node['type']
        nullable = node['nullable'] == true
        return [declared, nullable] unless declared.is_a?(Array)

        listed = declared.grep(String)
        [listed.reject { |type| type == NULL }.first, nullable || listed.include?(NULL)]
      end

      # @param node [Hash] a schema object
      # @param nullable [Boolean] as #type_of reported it
      # @return [Hash{Symbol => Object}] keys from IR::Field::CONSTRAINT_KEYS
      def self.call(node, nullable: false)
        constraints = KEYS.filter_map { |keyword, key| [key, node[keyword]] if node.key?(keyword) }
                          .to_h
        constraints[:nullable] = true if nullable
        exclusives(node, constraints)
      end

      # @param node [Hash]
      # @param constraints [Hash]
      # @return [Hash] the same constraints, with both dialects folded into one
      def self.exclusives(node, constraints)
        EXCLUSIVE.each do |keyword, (key, replaces)|
          value = node[keyword]
          next unless node.key?(keyword)

          constraints[key] = value if value.is_a?(Numeric)
          constraints[key] = constraints.delete(replaces) if value == true && constraints[replaces]
        end
        constraints
      end
    end
  end
end
