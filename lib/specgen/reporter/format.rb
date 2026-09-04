# frozen_string_literal: true

module SpecGen
  module Reporter
    # How a Derived value and its evidence look on screen, shared by every
    # section of the summary so the same fact never prints two ways.
    #
    #   derived(d)   "acmepay (heuristic 0.80)" or "unknown"
    #   evidence(d)  the evidence sentence, indented, only when asked for
    module Format
      INDENT = '  '

      # @param derived [IR::Derived, nil]
      # @return [String] value with its source and confidence
      def self.derived(derived)
        return 'unknown' if derived.nil? || derived.unknown?

        "#{derived.value} (#{derived.source} #{format('%.2f', derived.confidence)})"
      end

      # @param derived [IR::Derived, nil]
      # @param explain [Boolean] whether evidence is wanted at all
      # @param depth [Integer] indentation level of the line it explains
      # @return [Array<String>] zero or one line
      def self.evidence(derived, explain:, depth: 1)
        return [] unless explain && derived&.evidence

        ["#{INDENT * (depth + 1)}= #{derived.evidence}"]
      end

      # @param number [Integer]
      # @param noun [String] singular
      # @return [String] "1 schema", "8 schemas"
      def self.count(number, noun)
        "#{number} #{noun}#{'s' unless number == 1}"
      end

      # @param value [Object] a constraint value from the spec
      # @return [String] compact, without Ruby quoting for plain strings
      def self.constraint(value)
        case value
        when Array then value.map { |item| constraint(item) }.join(', ')
        when String then value
        else value.inspect
        end
      end
    end
  end
end
