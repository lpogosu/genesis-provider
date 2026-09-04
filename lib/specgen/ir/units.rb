# frozen_string_literal: true

module SpecGen
  module IR
    # In which unit the provider expects amounts, and the multiplier the
    # generated service applies to `operation.amount` (major units). Every
    # member is a Derived because each comes from a different place: the
    # currency from an enum or example, the unit from the type and example,
    # the exponent from ISO 4217.
    #
    #   currency   Derived<String> ISO 4217 code
    #   unit       Derived<Symbol> :minor | :major
    #   exponent   Derived<Integer> ISO 4217 minor unit exponent
    #   json_path  the amount field the units were derived for
    Units = Struct.new(:currency, :unit, :exponent, :json_path, keyword_init: true)

    # Vocabulary, defaults and arithmetic of Units.
    class Units
      include Node

      UNITS = %i[minor major].freeze
      UNDERIVED = 'not derived'

      # @param currency [Derived]
      # @param unit [Derived]
      # @param exponent [Derived]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(currency: Derived.unknown(evidence: UNDERIVED),
                     unit: Derived.unknown(evidence: UNDERIVED),
                     exponent: Derived.unknown(evidence: UNDERIVED), json_path: nil)
        Node.assert_derived!(currency, 'currency')
        Node.assert_derived!(unit, 'amount unit', allowed: UNITS)
        Node.assert_derived!(exponent, 'currency exponent')
        super
      end

      # @return [Integer, nil] factor from major to provider units; nil when
      #   it cannot be computed yet
      def multiplier
        return 1 if unit.value == :major
        return nil unless unit.value == :minor && exponent.known?

        10**exponent.value
      end

      # @return [Boolean]
      def known?
        !multiplier.nil?
      end

      # @return [Float] lowest confidence among the members the multiplier
      #   depends on; 0.0 when unknown
      def confidence
        return 0.0 unless known?

        members = unit.value == :major ? [unit] : [unit, exponent]
        members.map(&:confidence).min
      end
    end
  end
end
