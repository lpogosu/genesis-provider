# frozen_string_literal: true

module SpecGen
  module IR
    # A value together with where it came from. Every inferred member of the
    # IR is a Derived, because report.md has to explain each decision, and
    # the three levels of trust from CLAUDE.md are exactly this `source`:
    #
    #   :structural  read from the spec (required, enum, type)   confidence 1.0
    #   :overlay     stated by a human in an OpenAPI Overlay     confidence 1.0
    #   :registry    a standard or dictionary (ISO 4217, roles)  high
    #   :heuristic   inferred from structure or names            as measured
    #   :unknown     nothing to go on; the caller must also warn
    #
    #   value       the value itself, nil for :unknown
    #   source      one of Roles::SOURCE
    #   confidence  0.0..1.0, fixed at 1.0 for certain sources
    #   evidence    the sentence report.md prints, e.g. "ISO 4217: RUB
    #               exponent 2" or "name matcher: amount~sum (0.82)"
    Derived = Struct.new(:value, :source, :confidence, :evidence, keyword_init: true)

    # Factories, checks and predicates of Derived. Instances are frozen:
    # analyzers replace a Derived rather than mutate one, so a value can
    # never lose the evidence that explains it.
    class Derived
      include Node

      # A lookup table is exact, but a provider may deviate from the standard
      # (Adyen and ISK), which is why overlays exist and this is not 1.0.
      REGISTRY_CONFIDENCE = 0.9
      HEURISTIC_FALLBACK = 0.5
      RANGE = (0.0..1.0)

      # @param value [Object] read from the structure of the spec
      # @param evidence [String] which keyword it was read from
      # @return [Derived]
      def self.structural(value, evidence:)
        new(value: value, source: :structural, confidence: 1.0, evidence: evidence)
      end

      # @param value [Object] stated by a human in an overlay
      # @param evidence [String] which overlay action supplied it
      # @return [Derived]
      def self.overlay(value, evidence:)
        new(value: value, source: :overlay, confidence: 1.0, evidence: evidence)
      end

      # @param value [Object] taken from a standard or a dictionary
      # @param evidence [String] name the standard: "ISO 4217: JPY exponent 0"
      # @param confidence [Float]
      # @return [Derived]
      def self.registry(value, evidence:, confidence: REGISTRY_CONFIDENCE)
        new(value: value, source: :registry, confidence: confidence, evidence: evidence)
      end

      # @param value [Object] inferred from structure or names
      # @param confidence [Float] what the matchers actually scored
      # @param evidence [String] what each matcher contributed
      # @return [Derived]
      def self.heuristic(value, confidence:, evidence:)
        new(value: value, source: :heuristic, confidence: confidence, evidence: evidence)
      end

      # Nothing could be derived. The caller must add a Warning as well: an
      # unknown that nobody reports is how a silent gap reaches generated code.
      # @param evidence [String] what was looked for and not found
      # @return [Derived]
      def self.unknown(evidence:)
        new(value: nil, source: :unknown, confidence: 0.0, evidence: evidence)
      end

      # @param value [Object, nil]
      # @param source [Symbol] one of Roles::SOURCE
      # @param confidence [Float, nil] ignored for certain and unknown sources
      # @param evidence [String, nil]
      # @raise [ArgumentError] on an unknown source or an out-of-range confidence
      def initialize(value: nil, source: :unknown, confidence: nil, evidence: nil)
        super
        self.source = Roles.source!(source)
        self.confidence = settled_confidence
        self.evidence = evidence&.to_s
        freeze
      end

      # @return [Boolean] there is a value the generators can use
      def known?
        !value.nil? && source != :unknown
      end

      # @return [Boolean] an analyzer looked and derived nothing
      def unknown?
        !known?
      end

      # @return [Boolean] the value needs no human review
      def certain?
        Roles::CERTAIN_SOURCE.include?(source)
      end

      # @return [String] for report.md: ":minor (registry 0.90: ISO 4217 ...)"
      def to_s
        "#{value.inspect} (#{source} #{format('%.2f', confidence)}: #{evidence})"
      end

      private

      def settled_confidence
        return 1.0 if certain?
        return 0.0 if source == :unknown

        in_range(confidence || HEURISTIC_FALLBACK)
      end

      def in_range(number)
        unless number.is_a?(Numeric)
          raise ArgumentError,
                "confidence must be a number, got #{number.inspect}"
        end
        return number.to_f if RANGE.cover?(number)

        raise ArgumentError, "confidence must be within #{RANGE}, got #{number.inspect}"
      end
    end
  end
end
