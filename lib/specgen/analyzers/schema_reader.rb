# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Один объект схемы, превращённый в IR::Schema со своими полями.
    #
    # Вложенная структура не сплющивается и не теряется: свойство, которое
    # само объект или массив объектов, становится отдельной схемой, а поле
    # сохраняет своё имя. Именно это позволяет генератору собрать
    # `recipient: { type:, phone:, account: }`, а не непрозрачный хеш.
    # Вложенные схемы возвращаются наверх, а не регистрируются здесь: так
    # анализатор остаётся единственным, кто пишет в профиль, и может
    # остановить цикл по имени.
    #
    # Роли полей проставляет Matchers::Assigner — сразу всем полям схемы,
    # потому что конфликт «одна роль у двух полей» виден только на уровне
    # схемы. Без assigner (так читают другие анализаторы) роли остаются
    # невыведенными: сопоставлять имена с ролями в двух местах значило бы
    # получить два разных ответа.
    class SchemaReader
      # Что дала одна схема.
      #
      #   schema  IR::Schema вместе с полями
      #   nested  [[имя, узел, JSONPath]] схемы, которые регистрировать дальше
      #   notes   [Note] для записи анализатором
      Result = Struct.new(:schema, :nested, :notes, keyword_init: true)

      OBJECT = 'object'
      ARRAY = 'array'

      # @param name [String] имя, под которым схема попадёт в профиль
      # @param node [Object] объект схемы, `$ref` уже разрешены
      # @param at [String] JSONPath схемы
      # @param book [Rules::ConditionsBook] шаблоны условий в прозе
      # @param oas31 [Boolean]
      # @param assigner [Matchers::Assigner, nil] матчер ролей полей; nil —
      #   роли остаются невыведенными
      def initialize(name:, node:, at:, book:, oas31: false, assigner: nil)
        @name = name
        @at = at
        @book = book
        @oas31 = oas31
        @assigner = assigner
        @nested = []
        @notes = []
        @nodes = {}
        @node, composition = SchemaFlattener.call(node)
        composition.each { |code, message| add_note(code, message, @at) }
      end

      # @return [Result]
      def call
        required = required_of
        schema = IR::Schema.new(name: @name, type: type_of(@node), required: required,
                                description: text(@node['description']), json_path: @at)
        schema.fields = fields(required)
        assign_roles(schema.fields)
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

        add_note(:spec_element_unsupported, Texts.t('analyzers.schema.required_not_list'), at)
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

      # Из объекта, в котором ничего нет, нельзя собрать запрос, а сказать
      # спецификация что-то хотела; у скалярной схемы свойств нет законно.
      def no_properties
        return [] unless type_of(node) == OBJECT

        add_note(:spec_element_unsupported, Texts.t('analyzers.schema.object_without_properties'),
                 at)
        []
      end

      def field(name, body, required, conditions)
        path = "#{at}.properties#{SpecLoader::JsonPath.segment(name)}"
        return skip_property(name, path) unless body.is_a?(Hash)

        merged, composition = SchemaFlattener.call(body)
        composition.each { |code, message| add_note(code, message, path) }
        @nodes[name] = merged
        build(name, merged, required, conditions, path)
      end

      # Роли — всем полям схемы разом: так виден конфликт одной роли у двух
      # полей, а замечания матчеров становятся заметками анализатора.
      def assign_roles(fields)
        return if @assigner.nil? || fields.empty?

        subjects = fields.map { |field| RoleSubjects.field(field, @name, @nodes.fetch(field.name)) }
        @notes.concat(RoleSubjects.assign(@assigner, fields, subjects))
      end

      # Образец значения свойства. В OpenAPI 3.0 это `example`; в 3.1, где
      # схема — это JSON Schema 2020-12, законен ещё и `examples` МАССИВОМ
      # (не карту именованных примеров: та живёт на уровне media type, и её
      # читает ExampleReader). Без второй ветки обязательное поле, у которого
      # провайдер написал образец по правилам 3.1, уходило в payload как nil,
      # хотя значение в спецификации есть.
      def example_of(merged)
        return merged['example'] if merged.key?('example')

        list = merged['examples']
        list.is_a?(Array) ? list.first : nil
      end

      def build(name, merged, required, conditions, path)
        type, nullable = type_and_nullability(merged, name, path)
        IR::Field.new(name: name, role: pending_role, type: type, format: merged['format'],
                      required: required.include?(name), example: example_of(merged),
                      required_when: conditions.for(name, merged), json_path: path,
                      constraints: ConstraintReader.call(merged, nullable: nullable),
                      description: text(merged['description']),
                      schema: nested_schema(name, merged, path))
      end

      # Поле совсем без типа всё равно попадает в IR — выбросить его значило
      # бы потерять обязательное поле, — но отчёт обязан об этом сказать.
      def type_and_nullability(merged, name, path)
        type, nullable = ConstraintReader.type_of(merged)
        return [type, nullable] if type.is_a?(String)

        implied = implied_type(merged)
        if implied.nil?
          add_note(:format_unknown,
                   Texts.t('analyzers.schema.property_without_type', name: name), path)
        end
        [implied, nullable]
      end

      def implied_type(merged)
        return OBJECT if merged['properties'].is_a?(Hash)
        return ARRAY if merged.key?('items')

        nil
      end

      # @return [String, nil] имя вложенной схемы, на которую смотрит поле
      def nested_schema(name, merged, path)
        return items_schema(name, merged, path) if type_of(merged) == ARRAY

        register(merged, [@name, 'properties', name], path)
      end

      def items_schema(name, merged, path)
        items = merged['items']
        unless items.is_a?(Hash)
          add_note(:spec_element_unsupported,
                   Texts.t('analyzers.schema.array_without_items', name: name), path)
          return nil
        end

        register(items, [@name, 'properties', name, 'items'], "#{path}.items")
      end

      # Компонентная схема сохраняет своё имя и свой JSONPath, через какое
      # место использования её ни нашли бы: предупреждение или цель overlay
      # обязаны указывать на компонент, а не на копию, которую оставил здесь
      # резолвер. Инлайновый объект называется по месту, где стоит, — по тому
      # же правилу, по которому SchemaNaming называет операции.
      def register(body, context, path)
        component = SchemaNaming.component_of(body)
        name = component || (SchemaNaming.synthetic(context) if body['properties'].is_a?(Hash))
        return nil if name.nil?

        @nested << [name, body, component ? SchemaNaming.component_path(component) : path]
        name
      end

      def skip_property(name, path)
        add_note(:spec_element_unsupported,
                 Texts.t('analyzers.schema.property_not_object', name: name), path)
        nil
      end

      # Роль до матчеров; с assigner её заменит Matchers::Assigner.
      def pending_role
        IR::Derived.unknown(evidence: Texts.t('analyzers.schema.role_pending'))
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
