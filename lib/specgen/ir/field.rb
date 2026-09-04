# frozen_string_literal: true

module SpecGen
  module IR
    # One property of a schema.
    #
    #   name           property name verbatim (the only place the provider's
    #                  name survives; everything else keys by role)
    #   role           Derived<Symbol> one of Roles::FIELD, or unknown
    #   type           JSON Schema type verbatim ("string", "integer"...)
    #   format         JSON Schema format verbatim ("date-time", "uuid"...)
    #   required       true when listed in the parent's `required`
    #   required_when  RequiredWhen for a conditional requirement, else nil
    #   constraints    Hash with keys from CONSTRAINT_KEYS
    #   description    verbatim
    #   example        verbatim
    #   schema         name of the nested schema for objects, or of the item
    #                  schema for arrays; nil for scalars
    #   json_path      "$.components.schemas.X.properties.y"
    Field = Struct.new(:name, :role, :type, :format, :required, :required_when, :constraints,
                       :description, :example, :schema, :json_path, keyword_init: true)

    # Vocabulary and checks of Field.
    class Field
      include Node

      # JSON Schema validation keywords the generator uses, snake_cased.
      CONSTRAINT_KEYS = %i[
        enum const pattern minimum maximum exclusive_minimum exclusive_maximum
        min_length max_length min_items max_items multiple_of default nullable
      ].freeze

      # @param name [String]
      # @param role [Derived]
      # @param type [String, nil]
      # @param format [String, nil]
      # @param required [Boolean]
      # @param required_when [RequiredWhen, nil]
      # @param constraints [Hash{Symbol => Object}]
      # @param description [String, nil]
      # @param example [Object, nil]
      # @param schema [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, role:, type: nil, format: nil, required: false, required_when: nil,
                     constraints: {}, description: nil, example: nil, schema: nil, json_path: nil)
        Node.assert_text!(name, 'field name')
        Node.assert_derived!(role, 'field role', allowed: Roles::FIELD)
        Node.assert_optional!(required_when, RequiredWhen, 'required_when')
        check_constraints!(constraints)
        super
      end

      # @return [Boolean] unconditionally required
      def required?
        required == true
      end

      # @return [Boolean] required under a RequiredWhen condition
      def conditionally_required?
        !required_when.nil?
      end

      # @return [Array, nil] enum values when constrained
      def enum
        constraints[:enum]
      end

      # @return [Boolean] whether the field plays the given role
      def role?(role)
        self.role.value == Roles.field!(role)
      end

      private

      def check_constraints!(constraints)
        unless constraints.is_a?(Hash)
          raise ArgumentError, "constraints must be a Hash, got #{constraints.inspect}"
        end

        unknown = constraints.keys - CONSTRAINT_KEYS
        return if unknown.empty?

        raise ArgumentError,
              "unknown constraint keys #{unknown.inspect} (expected: #{CONSTRAINT_KEYS.join(', ')})"
      end
    end
  end
end
