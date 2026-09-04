# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Называет разобранное значение так, как автор спецификации прочитает
    # его в сообщении об ошибке: "object", "array", "string", а не "Hash" и
    # не "NilClass". Имена типов JSON Schema не переводятся ни на один язык:
    # это те же слова, что стоят в спецификации после `type:`, и
    # пользователь ищет их в своём файле.
    module TypeName
      NAMES = {
        Hash => 'object', Array => 'array', String => 'string', Integer => 'number',
        Float => 'number', TrueClass => 'boolean', FalseClass => 'boolean', NilClass => 'null'
      }.freeze

      # @param value [Object]
      # @return [String]
      def self.of(value)
        NAMES.fetch(value.class) { value.class.name.downcase }
      end
    end
  end
end
