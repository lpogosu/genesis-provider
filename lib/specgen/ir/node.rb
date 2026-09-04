# frozen_string_literal: true

module SpecGen
  module IR
    # Поведение, общее для каждого объекта-значения IR: глубокая сериализация
    # с устойчивым порядком ключей и проверки словаря, которые держат роли,
    # источники и действия внутри их закрытых списков.
    #
    # Типы IR — это Struct с инициализацией по ключам, подмешивающие этот
    # модуль. Struct закрепляет порядок полей, поэтому `to_h`
    # детерминирован и годится для golden-тестов; `dump` спускается во
    # вложенные объекты IR, массивы и хеши, так что в результате остаются
    # только обычные данные Ruby.
    module Node
      # Глубоко превращает значение IR в обычные данные.
      # @param value [Object] объект IR, Array, Hash или скаляр
      # @return [Object] Hash, Array или скаляр с развёрнутыми вложенными
      #   объектами IR
      def self.dump(value)
        case value
        when Node then value.to_h
        when Array then value.map { |item| dump(item) }
        when Hash then value.to_h { |key, item| [key, dump(item)] }
        else value
        end
      end

      # Поднимает ошибку, если `value` не принадлежит закрытому словарю.
      # @param allowed [Array<Symbol>] словарь
      # @param value [Object] проверяемое значение
      # @param what [String] название элемента для сообщения
      # @return [Object] само значение
      # @raise [ArgumentError] со списком допустимых значений
      def self.assert_member!(allowed, value, what)
        return value if allowed.include?(value)

        raise ArgumentError,
              "#{what}: неизвестное значение #{value.inspect} " \
              "(допустимо: #{allowed.join(', ')})"
      end

      # Поднимает ошибку, если `derived` не Derived или, при заданном
      # словаре, если его значение вне словаря.
      # @param derived [Derived]
      # @param what [String] название элемента для сообщения
      # @param allowed [Array<Symbol>, nil] словарь значения; nil — любое
      # @param allow_unknown [Boolean] принимать ли `Derived.unknown`
      # @return [Derived] сам аргумент
      # @raise [ArgumentError]
      def self.assert_derived!(derived, what, allowed: nil, allow_unknown: true)
        unless derived.is_a?(Derived)
          raise ArgumentError,
                "#{what}: ожидается Derived, получено #{derived.inspect}"
        end

        if derived.unknown?
          return derived if allow_unknown

          raise ArgumentError,
                "#{what}: значение обязано быть выведено; выбери явное значение по умолчанию"
        end
        assert_member!(allowed, derived.value, what) if allowed
        derived
      end

      # Поднимает ошибку, если `value` не непустая String.
      # @param value [Object]
      # @param what [String] название элемента для сообщения
      # @return [String] само значение
      # @raise [ArgumentError]
      def self.assert_text!(value, what)
        return value if value.is_a?(String) && !value.empty?

        raise ArgumentError, "#{what}: ожидается непустая строка, получено #{value.inspect}"
      end

      # Поднимает ошибку, если `value` не nil и не экземпляр `klass`.
      # @param value [Object]
      # @param klass [Class]
      # @param what [String] название элемента для сообщения
      # @return [Object] само значение
      # @raise [ArgumentError]
      def self.assert_optional!(value, klass, what)
        return value if value.nil? || value.is_a?(klass)

        raise ArgumentError, "#{what}: ожидается #{klass.name.split('::').last} или nil, " \
                             "получено #{value.inspect}"
      end

      # @return [Hash{Symbol => Object}] поля в порядке объявления, вложенные
      #   объекты IR развёрнуты в обычные данные
      def to_h
        super { |key, value| [key, Node.dump(value)] }
      end
    end
  end
end
