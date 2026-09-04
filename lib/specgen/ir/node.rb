# frozen_string_literal: true

module SpecGen
  module IR
    # Behaviour shared by every IR value object: deep serialisation with a
    # stable key order, and the vocabulary checks that keep roles, sources
    # and actions inside their closed lists.
    #
    # IR types are keyword-initialised Structs that include this module.
    # Struct fixes the member order, so `to_h` is deterministic and fit for
    # golden tests; `dump` recurses into nested IR objects, arrays and hashes
    # so the result contains only plain Ruby data.
    module Node
      # Deep-converts an IR value into plain data.
      # @param value [Object] IR object, Array, Hash or scalar
      # @return [Object] Hash, Array or scalar with nested IR objects converted
      def self.dump(value)
        case value
        when Node then value.to_h
        when Array then value.map { |item| dump(item) }
        when Hash then value.to_h { |key, item| [key, dump(item)] }
        else value
        end
      end

      # Raises unless `value` belongs to a closed vocabulary.
      # @param allowed [Array<Symbol>] the vocabulary
      # @param value [Object] value to check
      # @param what [String] noun for the message, e.g. "field role"
      # @return [Object] the value itself
      # @raise [ArgumentError] listing the accepted values
      def self.assert_member!(allowed, value, what)
        return value if allowed.include?(value)

        raise ArgumentError,
              "unknown #{what} #{value.inspect} (expected one of: #{allowed.join(', ')})"
      end

      # Raises unless `derived` is a Derived, optionally with a value from a
      # closed vocabulary.
      # @param derived [Derived]
      # @param what [String] noun for the message
      # @param allowed [Array<Symbol>, nil] vocabulary for the value, nil for any
      # @param allow_unknown [Boolean] accept `Derived.unknown`
      # @return [Derived] the argument itself
      # @raise [ArgumentError]
      def self.assert_derived!(derived, what, allowed: nil, allow_unknown: true)
        unless derived.is_a?(Derived)
          raise ArgumentError,
                "#{what} must be a Derived, got #{derived.inspect}"
        end

        if derived.unknown?
          return derived if allow_unknown

          raise ArgumentError, "#{what} must be known; pick an explicit fallback value"
        end
        assert_member!(allowed, derived.value, what) if allowed
        derived
      end

      # Raises unless `value` is a non-empty String.
      # @param value [Object]
      # @param what [String] noun for the message
      # @return [String] the value itself
      # @raise [ArgumentError]
      def self.assert_text!(value, what)
        return value if value.is_a?(String) && !value.empty?

        raise ArgumentError, "#{what} must be a non-empty String, got #{value.inspect}"
      end

      # Raises unless `value` is nil or an instance of `klass`.
      # @param value [Object]
      # @param klass [Class]
      # @param what [String] noun for the message
      # @return [Object] the value itself
      # @raise [ArgumentError]
      def self.assert_optional!(value, klass, what)
        return value if value.nil? || value.is_a?(klass)

        raise ArgumentError, "#{what} must be a #{klass.name.split('::').last} or nil, " \
                             "got #{value.inspect}"
      end

      # @return [Hash{Symbol => Object}] members in definition order, nested
      #   IR objects converted to plain data
      def to_h
        super { |key, value| [key, Node.dump(value)] }
      end
    end
  end
end
