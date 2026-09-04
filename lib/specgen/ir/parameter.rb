# frozen_string_literal: true

module SpecGen
  module IR
    # Параметр операции в path, query, header или cookie. Несёт роль так же,
    # как её несёт Field, потому что идентификаторы в пути, заголовки
    # идемпотентности и подписи — это параметры, а не поля тела.
    #
    #   name         дословно
    #   location     :path | :query | :header | :cookie
    #   role         Derived<Symbol>, одна из Roles::FIELD, либо не выведена
    #   required     дословно (параметры пути обязательны всегда)
    #   type         тип схемы дословно
    #   format       format схемы дословно
    #   description  дословно
    #   example      дословно
    #   json_path    "$.paths['/x'].post.parameters[0]" или путь компонента
    Parameter = Struct.new(:name, :location, :role, :required, :type, :format, :description,
                           :example, :json_path, keyword_init: true)

    # Словарь значений и проверки Parameter.
    class Parameter
      include Node

      LOCATIONS = %i[path query header cookie].freeze

      # @param name [String]
      # @param location [Symbol] одно из LOCATIONS
      # @param role [Derived]
      # @param required [Boolean]
      # @param type [String, nil]
      # @param format [String, nil]
      # @param description [String, nil]
      # @param example [Object, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, location:, role:, required: false, type: nil, format: nil,
                     description: nil, example: nil, json_path: nil)
        Node.assert_text!(name, 'имя параметра')
        Node.assert_member!(LOCATIONS, location, 'место параметра')
        Node.assert_derived!(role, 'роль параметра', allowed: Roles::FIELD)
        super
      end

      # @return [Boolean]
      def required?
        required == true
      end

      # @return [Boolean] играет ли параметр заданную роль
      def role?(role)
        self.role.value == Roles.field!(role)
      end
    end
  end
end
