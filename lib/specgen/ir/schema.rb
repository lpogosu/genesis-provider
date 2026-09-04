# frozen_string_literal: true

module SpecGen
  module IR
    # Именованная схема-объект со своими полями. Компонентные схемы
    # сохраняют имя компонента; инлайновые получают синтетическое имя от
    # анализатора (например, "getBalance.responses.200"), чтобы операции,
    # ответы и вебхуки могли ссылаться на любую схему по имени.
    #
    #   name         ключ внутри profile.schemas
    #   type         тип JSON Schema, обычно "object"
    #   description  дословно
    #   required     список `required` дословно
    #   fields       [Field]
    #   json_path    "$.components.schemas.X" или место инлайновой схемы
    Schema = Struct.new(:name, :type, :description, :required, :fields, :json_path,
                        keyword_init: true)

    # Проверки и выборки Schema.
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
        Node.assert_text!(name, 'имя схемы')
        super
      end

      # @param name [String] имя свойства
      # @return [Field, nil]
      def field(name)
        fields.find { |field| field.name == name }
      end

      # @param role [Symbol] одна из Roles::FIELD
      # @return [Array<Field>] поля с этой ролью, в порядке схемы
      def fields_by_role(role)
        Roles.field!(role)
        fields.select { |field| field.role.value == role }
      end

      # @return [Array<Field>] безусловно обязательные поля
      def required_fields
        fields.select(&:required?)
      end

      # @return [Array<Field>] поля, роль которых вывести не удалось
      def unresolved_fields
        fields.select { |field| field.role.unknown? }
      end
    end
  end
end
