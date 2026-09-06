# frozen_string_literal: true

module SpecGen
  module IR
    # Одно свойство схемы.
    #
    #   name           имя свойства дословно (единственное место, где имя от
    #                  провайдера сохраняется; всё остальное ключуется ролью)
    #   role           Derived<Symbol>, одна из Roles::FIELD, либо не выведена
    #   type           тип JSON Schema дословно ("string", "integer"...)
    #   format         format JSON Schema дословно ("date-time", "uuid"...)
    #   required       true, если поле перечислено в `required` родителя
    #   required_when  RequiredWhen для условной обязательности, иначе nil
    #   constraints    Hash с ключами из CONSTRAINT_KEYS
    #   description    дословно
    #   example        дословно
    #   schema         имя вложенной схемы для объектов или схемы элемента
    #                  для массивов; nil для скаляров
    #   variant        имя варианта `oneOf`/`anyOf`, из которого пришло поле;
    #                  nil у поля, объявленного самой схемой. Поля разных
    #                  вариантов провайдер вместе не принимает, поэтому
    #                  собирающий запрос обязан различать их, а не считать
    #                  соседями по одному объекту
    #   json_path      "$.components.schemas.X.properties.y"
    Field = Struct.new(:name, :role, :type, :format, :required, :required_when, :constraints,
                       :description, :example, :schema, :variant, :json_path, keyword_init: true)

    # Словарь значений и проверки Field.
    class Field
      include Node

      # Ключевые слова валидации JSON Schema, которыми пользуется генератор,
      # в snake_case.
      CONSTRAINT_KEYS = %i[
        enum const pattern minimum maximum exclusive_minimum exclusive_maximum
        min_length max_length min_items max_items multiple_of default nullable
      ].freeze

      # @param name [String]
      # @param role [Derived]
      # @param type [String, nil]
      # @param format [String, nil]
      # @param required [Boolean]
      # @param required_when [RequiredWhen, nil]
      # @param constraints [Hash{Symbol => Object}]
      # @param description [String, nil]
      # @param example [Object, nil]
      # @param schema [String, nil]
      # @param variant [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, role:, type: nil, format: nil, required: false, required_when: nil,
                     constraints: {}, description: nil, example: nil, schema: nil, variant: nil,
                     json_path: nil)
        Node.assert_text!(name, 'имя поля')
        Node.assert_derived!(role, 'роль поля', allowed: Roles::FIELD)
        Node.assert_optional!(required_when, RequiredWhen, 'required_when')
        check_constraints!(constraints)
        super
      end

      # @return [Boolean] обязательное безусловно
      def required?
        required == true
      end

      # @return [Boolean] обязательное при условии RequiredWhen
      def conditionally_required?
        !required_when.nil?
      end

      # @return [Boolean] поле пришло из ветки `oneOf`/`anyOf`, а не
      #   объявлено самой схемой
      def variant?
        !variant.nil?
      end

      # @return [Array, nil] значения enum, если поле ими ограничено
      def enum
        constraints[:enum]
      end

      # @return [Boolean] играет ли поле заданную роль
      def role?(role)
        self.role.value == Roles.field!(role)
      end

      private

      def check_constraints!(constraints)
        unless constraints.is_a?(Hash)
          raise ArgumentError, "constraints: ожидается Hash, получено #{constraints.inspect}"
        end

        unknown = constraints.keys - CONSTRAINT_KEYS
        return if unknown.empty?

        raise ArgumentError,
              "неизвестные ключи ограничений #{unknown.inspect} " \
              "(допустимо: #{CONSTRAINT_KEYS.join(', ')})"
      end
    end
  end
end
