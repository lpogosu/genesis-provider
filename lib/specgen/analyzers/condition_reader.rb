# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Why a field is required only sometimes.
    #
    # The order is the order of trust from CLAUDE.md. `dependentRequired`
    # and `if/then` are formal JSON Schema and are read as fact. OAS 3.0
    # forbids those keywords, so the registered `x-jsonschema-if` and
    # `x-jsonschema-then` extensions are read the same way. Only when the
    # schema says nothing formal do we look at the description - and a
    # condition read out of prose is a heuristic with a low confidence, a
    # warning and a ready-made overlay fragment, never a silent rule.
    #
    # A hint is accepted only when the name it captured is a sibling
    # property of the same schema. That single check throws out matches like
    # "minimum is 100" without any understanding of the sentence.
    class ConditionReader
      # Keyword pairs that express "if this, then required", in the order
      # they are trusted: native JSON Schema first, then the OpenAPI
      # extension registry spelling for 3.0.
      IF_KEYWORDS = [
        ['if', 'then', 'else', :if_then],
        ['x-jsonschema-if', 'x-jsonschema-then', 'x-jsonschema-else', :x_jsonschema_if]
      ].freeze
      DEPENDENT = 'dependentRequired'

      # @return [Array<Note>] what the caller should warn about
      attr_reader :notes

      # @param parent [Hash] the schema the field belongs to
      # @param properties [Array<String>] its property names
      # @param book [Rules::ConditionsBook] prose patterns
      # @param schema_path [String] JSONPath of the schema, for overlays
      # @param oas31 [Boolean] whether if/then may be written natively
      def initialize(parent:, properties:, book:, schema_path:, oas31: false)
        @parent = parent
        @properties = properties
        @book = book
        @schema_path = schema_path
        @oas31 = oas31
        @notes = []
      end

      # @param name [String] field name
      # @param node [Hash] the field's schema
      # @return [IR::RequiredWhen, nil]
      def for(name, node)
        dependent_required(name) || conditional(name) || hint(name, node)
      end

      private

      attr_reader :parent, :book, :schema_path

      def dependent_required(name)
        listed = parent[DEPENDENT]
        return nil unless listed.is_a?(Hash)

        trigger, = listed.find { |_, required| Array(required).include?(name) }
        return nil if trigger.nil?

        condition(field: trigger.to_s, equals: nil, origin: :dependent_required,
                  evidence: "#{DEPENDENT}: `#{trigger}` present makes `#{name}` required")
      end

      def conditional(name)
        IF_KEYWORDS.each do |if_key, then_key, else_key, origin|
          found = branch(if_key, then_key, name)
          note_negative(if_key, else_key, name)
          next if found.nil?

          trigger, value = found
          return condition(field: trigger, equals: value, origin: origin,
                           evidence: "#{if_key}/#{then_key}: #{describe(trigger, value)} makes " \
                                     "`#{name}` required")
        end
        nil
      end

      # @return [Array(String, Object), nil] the sibling and the value it takes
      def branch(if_key, then_key, name)
        test = parent[if_key]
        return nil unless test.is_a?(Hash)

        consequence = parent[then_key] || test['then']
        return nil unless consequence.is_a?(Hash) && required?(consequence, name)

        trigger_of(test)
      end

      # A negative branch cannot be expressed as "required when X equals Y",
      # so it is reported rather than silently dropped.
      def note_negative(if_key, else_key, name)
        otherwise = parent[else_key] || (parent[if_key].is_a?(Hash) ? parent[if_key]['else'] : nil)
        return unless otherwise.is_a?(Hash) && required?(otherwise, name)

        add_note(:conditional_required_hint,
                 "`#{name}` is required by the `#{else_key}` branch, a negative condition the " \
                 'IR cannot express; state it as a positive condition in an overlay',
                 severity: :warning)
      end

      def required?(node, name)
        node['required'].is_a?(Array) && node['required'].include?(name)
      end

      # @return [Array(String, Object), nil]
      def trigger_of(test)
        properties = test['properties']
        return nil unless properties.is_a?(Hash)

        name, body = properties.find { |_, value| value.is_a?(Hash) }
        return nil if name.nil?

        [name.to_s, body.key?('const') ? body['const'] : body['enum']]
      end

      def hint(name, node)
        found = book.match(node['description'])
        return nil if found.nil?

        pattern, match = found
        trigger = match[:field]
        return nil unless sibling?(trigger, name)

        value = pattern.kind == 'equals' ? match[:value] : nil
        hinted(name, node, trigger, value, pattern)
      end

      # The captured name has to be a property of the same schema, and not
      # the field itself; anything else is a sentence that happened to look
      # like a rule.
      def sibling?(trigger, name)
        !trigger.nil? && trigger != name && @properties.include?(trigger)
      end

      def hinted(name, node, trigger, value, pattern)
        sentence = node['description'].to_s.strip
        evidence = "description hint (#{pattern.name}): #{sentence.inspect} reads as " \
                   "#{describe(trigger, value)}"
        add_note(:conditional_required_hint,
                 "`#{name}` looks conditionally required (#{describe(trigger, value)}), but the " \
                 'schema states no condition; the fragment below states it formally',
                 suggested_overlay: overlay(name, trigger, value))
        condition(field: trigger, equals: value, origin: :description_hint, evidence: evidence,
                  confidence: book.hint_confidence)
      end

      def condition(field:, equals:, origin:, evidence:, confidence: nil)
        IR::RequiredWhen.new(field: field, equals: equals, origin: origin, evidence: evidence,
                             confidence: confidence)
      end

      def describe(trigger, value)
        return "`#{trigger}` present" if value.nil?

        "`#{trigger}` = #{Array(value).join(' | ')}"
      end

      # 3.1 takes if/then natively; 3.0 forbids them and takes the
      # registered extension instead. A presence condition is
      # dependentRequired in both.
      def overlay(name, trigger, value)
        return presence_overlay(name, trigger) if value.nil?

        if_key, then_key = @oas31 ? %w[if then] : %w[x-jsonschema-if x-jsonschema-then]
        <<~YAML
          - target: "#{schema_path}"
            update:
              #{if_key}:
                properties:
                  #{trigger}:
                    const: #{value}
              #{then_key}:
                required: [#{name}]
        YAML
      end

      def presence_overlay(name, trigger)
        <<~YAML
          - target: "#{schema_path}"
            update:
              #{DEPENDENT}:
                #{trigger}: [#{name}]
        YAML
      end

      def add_note(code, message, severity: :warning, suggested_overlay: nil)
        @notes << Note.new(code: code, message: message, json_path: schema_path,
                           severity: severity, suggested_overlay: suggested_overlay)
      end
    end
  end
end
