# frozen_string_literal: true

module SpecGen
  module Rules
    # Patterns that recognise a conditional requirement stated in prose.
    #
    # Formal conditions - `dependentRequired`, `if/then/else`, the registered
    # `x-jsonschema-*` extensions - are read straight from the schema and
    # need no dictionary. This file is for the other case: the only place
    # the spec says "required when the sibling equals this" is a sentence in
    # a description. Those words differ per provider and per language, and
    # the confidence of such a reading is a number to tune, so both live in
    # rules/ rather than in lib/.
    #
    # A pattern must capture `field`, the sibling the requirement depends
    # on. Capturing `value` as well makes it an equality condition; without
    # it the condition is about presence, which is what dependentRequired
    # means.
    class ConditionsBook < Book
      FILE = 'conditions.yml'
      KINDS = %w[equals presence].freeze
      FIELD_GROUP = 'field'
      VALUE_GROUP = 'value'
      FRACTION = (0.0..1.0)

      # One pattern as the analyzer uses it.
      #
      #   name       for the evidence line
      #   regexp     with a named group `field`, optionally `value`
      #   kind       "equals" or "presence"
      Hint = Struct.new(:name, :regexp, :kind, keyword_init: true)

      # @return [Array<Hint>] in dictionary order
      attr_reader :hints
      # @return [Float, nil] confidence of a condition read from prose
      attr_reader :hint_confidence

      # Text from a spec is UTF-8, but a file read in another encoding would
      # make Regexp#match raise rather than simply not match; a description
      # we cannot read is a description with no hint in it.
      # @param description [String, nil]
      # @return [Array(Hint, MatchData), nil] the first pattern that matches
      def match(description)
        return nil unless description.is_a?(String) && description.valid_encoding?

        hints.each do |hint|
          found = hint.regexp.match(description)
          return [hint, found] unless found.nil?
        end
        nil
      rescue Encoding::CompatibilityError
        nil
      end

      private

      def build
        section = mapping(data['required_when'], 'required_when', path('required_when'))
        @hint_confidence = confidence_of(section['confidence'])
        @hints = load_hints(section['patterns'])
      end

      def confidence_of(value)
        at = path('required_when', 'confidence')
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        complain("confidence must be a number within #{FRACTION}, got #{describe(value)}", at)
        nil
      end

      def load_hints(listed)
        at = path('required_when', 'patterns')
        unless listed.is_a?(Array) && !listed.empty?
          complain("patterns must be a non-empty array, got #{describe(listed)}", at)
          return [].freeze
        end

        listed.each_with_index.filter_map { |body, index| hint(body, "#{at}[#{index}]") }.freeze
      end

      def hint(body, at)
        fields = mapping(body, 'pattern entry', at)
        name = text(fields['name'], 'pattern name', "#{at}.name")
        regexp = pattern(fields['pattern'], 'pattern', "#{at}.pattern")
        kind = kind_of(fields['kind'], at)
        return nil if name.nil? || regexp.nil? || kind.nil? || !captures?(regexp, kind, at)

        Hint.new(name: name, regexp: regexp, kind: kind).freeze
      end

      def kind_of(value, at)
        return value if KINDS.include?(value)

        complain("kind must be one of #{KINDS.join(', ')}, got #{describe(value)}", "#{at}.kind")
        nil
      end

      # Without the named groups the analyzer has nothing to build a
      # condition from, so a pattern that lacks them is a broken entry.
      def captures?(regexp, kind, at)
        names = regexp.names
        missing = [FIELD_GROUP] - names
        missing << VALUE_GROUP if kind == 'equals' && !names.include?(VALUE_GROUP)
        return true if missing.empty?

        complain("pattern must capture #{missing.join(', ')} as a named group", "#{at}.pattern")
        false
      end
    end
  end
end
