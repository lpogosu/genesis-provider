# frozen_string_literal: true

module SpecGen
  module IR
    # A named object schema with its fields. Component schemas keep their
    # component name; inline schemas get a synthetic name from the analyzer
    # (e.g. "getBalance.responses.200") so that operations, responses and
    # webhooks can reference every schema by name.
    #
    #   name         key under profile.schemas
    #   type         JSON Schema type, normally "object"
    #   description  verbatim
    #   required     the `required` list verbatim
    #   fields       [Field]
    #   json_path    "$.components.schemas.X" or the inline location
    Schema = Struct.new(:name, :type, :description, :required, :fields, :json_path,
                        keyword_init: true)

    # Checks and lookups of Schema.
    class Schema
      include Node

      # @param name [String]
      # @param type [String]
      # @param description [String, nil]
      # @param required [Array<String>]
      # @param fields [Array<Field>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, type: 'object', description: nil, required: [], fields: [],
                     json_path: nil)
        Node.assert_text!(name, 'schema name')
        super
      end

      # @param name [String] property name
      # @return [Field, nil]
      def field(name)
        fields.find { |field| field.name == name }
      end

      # @param role [Symbol] one of Roles::FIELD
      # @return [Array<Field>] fields playing that role, in schema order
      def fields_by_role(role)
        Roles.field!(role)
        fields.select { |field| field.role.value == role }
      end

      # @return [Array<Field>] unconditionally required fields
      def required_fields
        fields.select(&:required?)
      end

      # @return [Array<Field>] fields whose role could not be derived
      def unresolved_fields
        fields.select { |field| field.role.unknown? }
      end
    end
  end
end
