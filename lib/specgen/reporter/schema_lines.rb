# frozen_string_literal: true

module SpecGen
  module Reporter
    # Секция схем в сводке: каждая схема с каждым полем — тип и формат,
    # обязательность, ограничения из спецификации. Поле с условной
    # обязательностью говорит об этом в своей строке вместе с происхождением
    # условия: «обязательно при type = card», прочитанное из прозы описания,
    # и то же правило из dependentRequired — разный уровень доверия.
    #
    # Роли полей печатаются только после того, как их проставит матчер:
    # колонка из одних «не выведено» до появления матчеров не сказала бы
    # ничего.
    class SchemaLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] печатать обоснование присвоенных ролей
      def initialize(profile, explain: false)
        @schemas = profile.schemas.values
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return [Texts.t('summary.schemas_none')] if @schemas.empty?

        [Texts.t('summary.schemas')] + @schemas.flat_map { |schema| schema_lines(schema) }
      end

      private

      def schema_lines(schema)
        heading = "#{INDENT}#{schema.name} (#{Texts.plural(schema.fields.size, 'field')})"
        [heading] + schema.fields.flat_map { |field| field_lines(field) }
      end

      def field_lines(field)
        [field_line(field), *Format.evidence(field.role, explain: @explain, depth: 2)]
      end

      def field_line(field)
        columns = [(INDENT * 2) + field.name.ljust(name_width),
                   type_text(field).ljust(type_width),
                   requiredness(field).ljust(requiredness_width)]
        details = details(field)
        columns << details unless details.empty?
        columns.join('  ').rstrip
      end

      def type_text(field)
        [field.type || '?', field.format].compact.join(' ')
      end

      def requiredness(field)
        Texts.t(field.required? ? 'summary.field_required' : 'summary.field_optional')
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
        common = { field: condition.field, origin: Texts.t("origin.#{condition.origin}"),
                   confidence: format('%.2f', condition.confidence) }
        return Texts.t('summary.required_when_present', **common) if condition.presence?

        Texts.t('summary.required_when_equals', value: Format.constraint(condition.equals),
                                                **common)
      end

      def name_width
        @name_width ||= fields.map { |field| field.name.size }.max || 0
      end

      def type_width
        @type_width ||= fields.map { |field| type_text(field).size }.max || 0
      end

      def requiredness_width
        @requiredness_width ||= %w[summary.field_required summary.field_optional]
                                .map { |key| Texts.t(key).size }.max
      end

      def fields
        @fields ||= @schemas.flat_map(&:fields)
      end
    end
  end
end
