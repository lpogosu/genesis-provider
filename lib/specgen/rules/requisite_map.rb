# frozen_string_literal: true

module SpecGen
  module Rules
    # Таблица `platform.requisites` контракта: где платформа держит реквизиты
    # получателя. Плоских полей у операции нет — всё лежит в JSONB-хеше, и
    # ключ верхнего уровня в нём это payment_method шлюза, он же
    # request_method. Отсюда двухуровневая таблица «способ выплаты → роль →
    # выражение», а из неё — ветка по request_method в сгенерированном коде.
    #
    # Роли, для которой выражения здесь нет, не существует и в сервисе:
    # догадка о платформе запрещена (эксперты кейса, 5 сентября 2026,
    # вопрос 25), поэтому поле получает TODO, а не выдуманный ключ хеша.
    class RequisiteMap
      include Checks

      # @return [String, nil] выражение с самим хешем реквизитов
      attr_reader :hash_expression

      # @param data [Object] значение ключа `requisites`
      # @param file [String] файл справочника, для сообщений
      # @param at [String] JSONPath раздела
      # @param problems [Problems] общий сборщик проблем
      def initialize(data, file:, at:, problems:)
        @file = file
        @problems = problems
        @at = at
        section = mapping(data, noun(:platform_map, key: 'requisites'), at, required: false)
        @hash_expression = hash_of(section)
        load_methods(section['methods'])
        freeze
      end

      # @return [Array<String>] способы выплаты платформы в порядке справочника
      def payment_methods
        @methods.keys
      end

      # @param method [String] способ выплаты платформы
      # @param role [Symbol] роль поля
      # @return [String, nil] выражение со значением реквизита
      def expression(method, role)
        @methods.dig(method, role)
      end

      # @param role [Symbol] роль поля
      # @return [Boolean] хоть один способ выплаты знает эту роль
      def role?(role)
        @methods.any? { |_method, table| table.key?(role) }
      end

      # @param role [Symbol] роль поля
      # @return [Array<String>] способы выплаты, у которых роль есть
      def payment_methods_for(role)
        @methods.select { |_method, table| table.key?(role) }.keys
      end

      # @return [Array<Symbol>] роли, названные хотя бы одним способом выплаты
      def roles
        @methods.values.flat_map(&:keys).uniq
      end

      private

      def hash_of(section)
        return nil unless section.key?('hash')

        text(section['hash'], noun(:expression, key: 'hash'), "#{@at}.hash")
      end

      def load_methods(data)
        at = "#{@at}.methods"
        table = mapping(data, noun(:platform_map, key: 'methods'), at, required: false)
        @methods = table.to_h { |name, body| [name.to_s, entries(name, body)] }.freeze
      end

      def entries(name, body)
        at = "#{@at}.methods.#{name}"
        table = mapping(body, noun(:platform_map, key: name), at, required: false)
        table.filter_map { |role, expression| entry(name, role, expression) }.to_h.freeze
      end

      def entry(name, role, expression)
        at = "#{@at}.methods.#{name}.#{role}"
        symbol = symbol_in(role, IR::Roles::FIELD, noun(:field_role), at)
        value = text(expression, noun(:expression, key: role), at)
        symbol && value && [symbol, value]
      end

      def complain(message, at)
        @problems.add(message, file: @file, path: at)
      end
    end
  end
end
