# frozen_string_literal: true

module SpecGen
  module Rules
    # ISO 4217: the minor-unit exponent of every currency code.
    #
    # The exponent decides the multiplier the generated service applies to
    # `operation.amount`, so it is read from the standard and never from the
    # word "копейки" in a description. A provider that deviates from the
    # standard is corrected with an OpenAPI Overlay, not by editing this
    # table: the table states what ISO says, the overlay states what the
    # provider does.
    class CurrenciesBook < Book
      FILE = 'currencies.yml'
      CODE = /\A[A-Z]{3}\z/
      # ISO 4217 uses 0 to 4; anything else is a typo in the table.
      EXPONENT_RANGE = (0..4)
      # Only reached when the table itself is invalid and the load is about
      # to raise anyway; it keeps the remaining checks running.
      FALLBACK_EXPONENT = 2

      # @return [Integer] exponent for an unknown code; usable only together
      #   with a warning, never silently
      attr_reader :default_exponent

      # @param code [String] ISO 4217 alphabetic code
      # @return [Integer, nil] minor unit exponent, nil when the code is unknown
      def exponent(code)
        entry(code)&.fetch(:exponent)
      end

      # @param code [String]
      # @return [String, nil] English name of the currency
      def name_of(code)
        entry(code)&.fetch(:name)
      end

      # @param code [String]
      # @return [Boolean]
      def known?(code)
        !entry(code).nil?
      end

      # @return [Array<String>] every code in the table
      def codes
        @currencies.keys
      end

      private

      def entry(code)
        @currencies[code.to_s.strip.upcase]
      end

      def build
        @default_exponent = integer(data['default_exponent'], 'default exponent',
                                    path('default_exponent'),
                                    range: EXPONENT_RANGE) || FALLBACK_EXPONENT
        @currencies = {}
        section('currencies').each { |code, body| add(code, body) }
        complain('the table is empty', path('currencies')) if @currencies.empty?
        @currencies.freeze
      end

      def add(code, body)
        at = path('currencies', code)
        unless code.is_a?(String) && code.match?(CODE)
          complain("currency code must be three capital letters, got #{code.inspect}", at)
          return
        end
        fields = mapping(body, "currency #{code}", at)
        record(code, fields, at)
      end

      def record(code, fields, at)
        exponent = integer(fields['exponent'], 'exponent', "#{at}.exponent",
                           range: EXPONENT_RANGE)
        name = text(fields['name'], 'currency name', "#{at}.name")
        return if exponent.nil? || name.nil?

        @currencies[code] = { exponent: exponent, name: name }.freeze
      end
    end
  end
end
