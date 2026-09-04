# frozen_string_literal: true

module SpecGen
  module IR
    # Conditional requirement of a field: "required when sibling `field`
    # equals `equals`", or, with `equals` nil, "required when sibling
    # `field` is present" (the dependentRequired semantics).
    #
    #   field       name of the sibling the condition looks at
    #   equals      value or Array of values; nil for a presence condition
    #   origin      one of ORIGINS; where the condition was read from
    #   evidence    one line for the report
    #   confidence  1.0 for formal origins, given explicitly for a
    #               description hint
    RequiredWhen = Struct.new(:field, :equals, :origin, :evidence, :confidence, keyword_init: true)

    # Vocabulary and checks of RequiredWhen.
    class RequiredWhen
      include Node

      ORIGINS = %i[
        dependent_required if_then x_jsonschema_if discriminator overlay description_hint
      ].freeze
      # Which Derived source each origin corresponds to.
      SOURCE_BY_ORIGIN = {
        dependent_required: :structural, if_then: :structural, x_jsonschema_if: :structural,
        discriminator: :structural, overlay: :overlay, description_hint: :heuristic
      }.freeze

      # @param field [String] sibling field name
      # @param origin [Symbol] one of ORIGINS
      # @param evidence [String]
      # @param equals [Object, Array, nil]
      # @param confidence [Float, nil] required for :description_hint only
      # @raise [ArgumentError]
      def initialize(field:, origin:, evidence:, equals: nil, confidence: nil)
        Node.assert_text!(field, 'condition field')
        Node.assert_member!(ORIGINS, origin, 'condition origin')
        Node.assert_text!(evidence, 'condition evidence')
        confidence = resolve_confidence(origin, confidence)
        super
      end

      # @return [Symbol] Derived source implied by the origin
      def source
        SOURCE_BY_ORIGIN.fetch(origin)
      end

      # @return [Boolean] read from schema keywords or an overlay, not prose
      def formal?
        source != :heuristic
      end

      # @return [Boolean] "required when `field` is present" rather than equal
      def presence?
        equals.nil?
      end

      # @return [Array] the accepted values of the sibling, empty for presence
      def values
        Array(equals)
      end

      private

      def resolve_confidence(origin, given)
        return formal_confidence(origin, given) if SOURCE_BY_ORIGIN.fetch(origin) != :heuristic

        raise ArgumentError, "confidence is required for #{origin.inspect}" if given.nil?
        unless given.is_a?(Numeric) && given.between?(0.0, 1.0)
          raise ArgumentError, "confidence must be within 0.0..1.0, got #{given.inspect}"
        end

        given.to_f
      end

      # A condition read from schema keywords or stated in an overlay is not
      # a guess, so its confidence is fixed rather than taken on trust.
      def formal_confidence(origin, given)
        return 1.0 if given.nil? || full?(given)

        raise ArgumentError,
              "confidence for #{origin.inspect} is fixed at 1.0, got #{given.inspect}"
      end

      def full?(given)
        number = Float(given, exception: false)
        !number.nil? && (number - 1.0).abs < Float::EPSILON
      end
    end
  end
end
