# frozen_string_literal: true

module SpecGen
  module Analyzers
    # One schema object turned into an IR::Schema with its fields.
    #
    # Nested structure is not flattened and not lost: a property that is an
    # object, or an array of objects, becomes a schema of its own, and the
    # field keeps its name. That is what lets a generator build
    # `recipient: { type:, phone:, bank_code: }` instead of an opaque hash.
    # The nested schemas are handed back rather than registered here, so the
    # analyzer stays the only place that writes to the profile and can stop
    # a cycle by name.
    #
    # Field roles are deliberately left unknown: matching names to roles is
    # the field matchers' job, and two places guessing would disagree.
    class SchemaReader
      # What one schema produced.
      #
      #   schema  IR::Schema, fields included
      #   nested  [[name, node, json_path]] schemas to register next
      #   notes   [Note] for the analyzer to record
      Result = Struct.new(:schema, :nested, :notes, keyword_init: true)

      ROLE_PENDING = 'field roles are matched by the field matchers, a later stage'
      OBJECT = 'object'
      ARRAY = 'array'

      # @param name [String] name the schema is filed under
      # @param node [Object] the schema object, `$ref`s already resolved
      # @param at [String] JSONPath of the schema
      # @param book [Rules::ConditionsBook] prose patterns for conditions
      # @param oas31 [Boolean]
      def initialize(name:, node:, at:, book:, oas31: false)
        @name = name
        @at = at
        @book = book
        @oas31 = oas31
        @nested = []
        @notes = []
        @node, composition = SchemaFlattener.call(node)
        composition.each { |code, message| add_note(code, message, @at) }
      end

      # @return [Result]
      def call
        required = required_of
        schema = IR::Schema.new(name: @name, type: type_of(@node), required: required,
                                description: text(@node['description']), json_path: @at)
        schema.fields = fields(required)
        Result.new(schema: schema, nested: @nested, notes: @notes)
      end

      private

      attr_reader :node, :at

      def type_of(body)
        type, = ConstraintReader.type_of(body)
        return type if type.is_a?(String)

        body['properties'].is_a?(Hash) ? OBJECT : nil
      end

      def required_of
        listed = node['required']
        return listed.grep(String) if listed.is_a?(Array)
        return [] if listed.nil?

        add_note(:spec_element_unsupported, '`required` must be a list of property names', at)
        []
      end

      def fields(required)
        properties = node['properties']
        return no_properties unless properties.is_a?(Hash) && !properties.empty?

        conditions = ConditionReader.new(parent: node, properties: properties.keys, book: @book,
                                         schema_path: at, oas31: @oas31)
        list = properties.filter_map { |name, body| field(name.to_s, body, required, conditions) }
        @notes.concat(conditions.notes)
        list
      end

      # An object with nothing in it cannot be built into a request, and the
      # spec meant to say something; a scalar schema legitimately has none.
      def no_properties
        return [] unless type_of(node) == OBJECT

        add_note(:spec_element_unsupported,
                 'the schema is an object but declares no properties, so nothing can be built ' \
                 'from it', at)
        []
      end

      def field(name, body, required, conditions)
        path = "#{at}.properties#{SpecLoader::JsonPath.segment(name)}"
        return skip_property(name, path) unless body.is_a?(Hash)

        merged, composition = SchemaFlattener.call(body)
        composition.each { |code, message| add_note(code, message, path) }
        build(name, merged, required, conditions, path)
      end

      def build(name, merged, required, conditions, path)
        type, nullable = type_and_nullability(merged, name, path)
        IR::Field.new(name: name, role: pending_role, type: type, format: merged['format'],
                      required: required.include?(name), example: merged['example'],
                      required_when: conditions.for(name, merged), json_path: path,
                      constraints: ConstraintReader.call(merged, nullable: nullable),
                      description: text(merged['description']),
                      schema: nested_schema(name, merged, path))
      end

      # A property with no type at all still goes into the IR - dropping it
      # would lose a required field - but the report has to say so.
      def type_and_nullability(merged, name, path)
        type, nullable = ConstraintReader.type_of(merged)
        return [type, nullable] if type.is_a?(String)

        implied = implied_type(merged)
        if implied.nil?
          add_note(:format_unknown,
                   "property `#{name}` declares no `type`, so the generated code cannot check " \
                   'or coerce its value', path)
        end
        [implied, nullable]
      end

      def implied_type(merged)
        return OBJECT if merged['properties'].is_a?(Hash)
        return ARRAY if merged.key?('items')

        nil
      end

      # @return [String, nil] name of the nested schema this field points at
      def nested_schema(name, merged, path)
        return items_schema(name, merged, path) if type_of(merged) == ARRAY

        register(merged, [@name, 'properties', name], path)
      end

      def items_schema(name, merged, path)
        items = merged['items']
        unless items.is_a?(Hash)
          add_note(:spec_element_unsupported,
                   "array `#{name}` declares no `items`, so its element type is unknown", path)
          return nil
        end

        register(items, [@name, 'properties', name, 'items'], "#{path}.items")
      end

      # A component keeps its name and its own JSONPath, whichever use site
      # it was reached through - a warning or an overlay target has to point
      # at the component, not at the copy the resolver left here. An inline
      # object is named after where it sits, by the same rule SchemaNaming
      # gives the operations.
      def register(body, context, path)
        component = SchemaNaming.component_of(body)
        name = component || (SchemaNaming.synthetic(context) if body['properties'].is_a?(Hash))
        return nil if name.nil?

        @nested << [name, body, component ? SchemaNaming.component_path(component) : path]
        name
      end

      def skip_property(name, path)
        add_note(:spec_element_unsupported, "property `#{name}` must be an object; it was skipped",
                 path)
        nil
      end

      def pending_role
        IR::Derived.unknown(evidence: ROLE_PENDING)
      end

      def text(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end

      def add_note(code, message, path, severity: :warning)
        @notes << Note.new(code: code, message: message, json_path: path, severity: severity)
      end
    end
  end
end
