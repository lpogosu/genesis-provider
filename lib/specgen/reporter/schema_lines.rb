# frozen_string_literal: true

module SpecGen
  module Reporter
    # The schemas section of the summary: every schema with every field, its
    # type and format, whether it is required, and the constraints the spec
    # states. A field with a conditional requirement says so on its line,
    # with the origin of the condition, because "required when type = card"
    # read from prose and the same rule read from dependentRequired are not
    # the same level of trust.
    #
    # Field roles print only once a matcher has assigned one; a column of
    # "unknown" before the matchers exist would say nothing.
    class SchemaLines
      INDENT = Format::INDENT
      REQUIRED = { true => 'required', false => 'optional' }.freeze

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] print the evidence behind assigned roles
      def initialize(profile, explain: false)
        @schemas = profile.schemas.values
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return ['Schemas: none'] if @schemas.empty?

        ['Schemas:'] + @schemas.flat_map { |schema| schema_lines(schema) }
      end

      private

      def schema_lines(schema)
        heading = "#{INDENT}#{schema.name} (#{Format.count(schema.fields.size, 'field')})"
        [heading] + schema.fields.flat_map { |field| field_lines(field) }
      end

      def field_lines(field)
        [field_line(field), *Format.evidence(field.role, explain: @explain, depth: 2)]
      end

      def field_line(field)
        columns = [(INDENT * 2) + field.name.ljust(name_width),
                   type_text(field).ljust(type_width),
                   REQUIRED.fetch(field.required?)]
        details = details(field)
        columns << details unless details.empty?
        columns.join('  ')
      end

      def type_text(field)
        [field.type || '?', field.format].compact.join(' ')
      end

      def details(field)
        parts = []
        parts << "role=#{field.role.value}" if field.role.known?
        parts << "-> #{field.schema}" if field.schema
        parts.concat(field.constraints.map { |key, value| "#{key}=#{Format.constraint(value)}" })
        parts << condition(field.required_when) if field.required_when
        parts.join('  ')
      end

      def condition(condition)
        clause = if condition.presence?
                   "#{condition.field} present"
                 else
                   "#{condition.field} = #{Format.constraint(condition.equals)}"
                 end
        origin = condition.origin.to_s.tr('_', ' ')
        "required when #{clause} (#{origin} #{format('%.2f', condition.confidence)})"
      end

      def name_width
        @name_width ||= fields.map { |field| field.name.size }.max || 0
      end

      def type_width
        @type_width ||= fields.map { |field| type_text(field).size }.max || 0
      end

      def fields
        @fields ||= @schemas.flat_map(&:fields)
      end
    end
  end
end
