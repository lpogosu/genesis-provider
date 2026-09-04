# frozen_string_literal: true

module SpecGen
  module Rules
    # The checks every dictionary needs: a value out of a closed vocabulary,
    # a non-empty string, a whole number in range, a list of strings, a
    # pattern that compiles. Each records the problem and returns nil (or an
    # empty list) rather than raising, so one load reports every mistake in
    # every file instead of stopping at the first.
    #
    # Mixed into Book, which supplies #complain.
    module Checks
      # @param value [Object] value as written in the dictionary
      # @param allowed [Array<Symbol>] the closed vocabulary
      # @param what [String] noun for the message, e.g. "field role"
      # @param at [String] JSONPath of the value
      # @return [Symbol, nil]
      def symbol_in(value, allowed, what, at)
        symbol = value.is_a?(String) ? value.to_sym : value
        return symbol if allowed.include?(symbol)

        complain("unknown #{what} #{value.inspect} (expected one of: #{allowed.join(', ')})", at)
        nil
      end

      # @param what [String] noun for the message
      # @param at [String] JSONPath of the value
      # @return [String, nil]
      def text(value, what, at)
        return value if value.is_a?(String) && !value.strip.empty?

        complain("#{what} must be a non-empty string, got #{describe(value)}", at)
        nil
      end

      # @param range [Range, nil] accepted values, nil for any whole number
      # @return [Integer, nil]
      def integer(value, what, at, range: nil)
        unless value.is_a?(Integer)
          complain("#{what} must be a whole number, got #{describe(value)}", at)
          return nil
        end
        return value if range.nil? || range.cover?(value)

        complain("#{what} must be within #{range}, got #{value}", at)
        nil
      end

      # @param required [Boolean] whether an absent list is a problem
      # @return [Array<String>] the entries that passed; empty on a bad list
      def string_list(value, what, at, required: true)
        return [] if value.nil? && !required

        unless value.is_a?(Array) && !value.empty?
          complain("#{what} must be a non-empty array, got #{describe(value)}", at)
          return []
        end

        value.each_with_index.filter_map do |item, index|
          text(item, "#{what} entry", "#{at}[#{index}]")
        end
      end

      # @return [Regexp, nil]
      def pattern(value, what, at)
        source = text(value, what, at)
        return nil if source.nil?

        Regexp.new(source)
      rescue RegexpError => e
        complain("#{what} is not a valid regular expression: #{e.message}", at)
        nil
      end

      # @param required [Boolean] whether an absent object is a problem
      # @return [Hash] the object itself, or an empty one with a problem recorded
      def mapping(value, what, at, required: true)
        return value if value.is_a?(Hash)
        return {} if value.nil? && !required

        complain("#{what} must be an object, got #{describe(value)}", at)
        {}
      end

      # @return [String] the value the way a dictionary author reads it
      def describe(value)
        return 'nothing' if value.nil?

        "#{SpecLoader::TypeName.of(value)} #{value.inspect}"
      end
    end
  end
end
