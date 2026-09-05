# frozen_string_literal: true

module SpecGen
  module Rules
    # Раздел `platform` контракта: как сгенерированный сервис читает данные
    # операции платформы, находит операцию по идентификатору из уведомления,
    # запоминает идентификатор провайдера, разбирает аргумент колбэка и
    # результат базового класса.
    #
    # Всё это выражения Ruby, которые шаблон подставляет как есть. Реального
    # класса Operation нам не выдали, поэтому раздел целиком — допущение, и
    # именно поэтому он данные: поменялась платформа — правится YAML, а не
    # шаблон. Ключи таблиц — роли полей из IR::Roles::FIELD; роль вне словаря
    # останавливает загрузку, как и везде в справочниках.
    class PlatformBindings
      include Checks

      # Таблицы «роль → выражение» и обязателен ли в выражении %{value}.
      MAPS = { accessors: false, lookup: true, writers: true }.freeze
      VALUE_TOKEN = '%{value}'

      # @return [String, nil] источник раздела, для документации
      attr_reader :source
      # @return [String, nil] выражение с сырым телом входящего уведомления
      attr_reader :callback_body
      # @return [String, nil] выражение с заголовками входящего уведомления
      attr_reader :callback_headers
      # @return [String, nil] имя предиката успешного результата базового
      #   класса, например "success?"
      attr_reader :success_predicate

      # @param data [Object] значение ключа `platform` из contract.yml
      # @param file [String] файл справочника, для сообщений
      # @param problems [Problems] общий сборщик проблем
      def initialize(data, file:, problems:)
        @file = file
        @problems = problems
        @at = SpecLoader::JsonPath.build(['platform'])
        section = mapping(data, noun(:platform_section), @at, required: false)
        load_maps(section)
        load_scalars(section)
        freeze
      end

      # @param role [Symbol] роль поля
      # @return [String, nil] выражение со значением для тела запроса
      def accessor(role)
        @maps[:accessors][role]
      end

      # @param role [Symbol] роль идентификатора
      # @param value [String] выражение со значением из уведомления
      # @return [String, nil] выражение, находящее операцию платформы
      def lookup(role, value)
        fill(@maps[:lookup][role], value)
      end

      # @param role [Symbol] роль идентификатора
      # @param value [String] выражение со значением из ответа
      # @return [String, nil] выражение, сохраняющее значение в операции
      def writer(role, value)
        fill(@maps[:writers][role], value)
      end

      # @param kind [Symbol] одна из MAPS
      # @return [Array<Symbol>] роли, для которых таблица задана, по порядку
      #   справочника
      def roles(kind)
        @maps.fetch(kind).keys
      end

      private

      def fill(expression, value)
        expression && format(expression, value: value)
      end

      def load_maps(section)
        @maps = MAPS.to_h do |key, needs_value|
          table = mapping(section[key.to_s], noun(:platform_map, key: key), "#{@at}.#{key}",
                          required: false)
          [key, table.filter_map { |role, expr| entry(key, role, expr, needs_value) }.to_h.freeze]
        end.freeze
      end

      def entry(key, role, expression, needs_value)
        at = "#{@at}.#{key}.#{role}"
        symbol = symbol_in(role, IR::Roles::FIELD, noun(:field_role), at)
        text = text(expression, noun(:expression, key: role), at)
        return nil if symbol.nil? || text.nil?
        return [symbol, text] if !needs_value || text.include?(VALUE_TOKEN)

        fault('contract.expression_needs_value', at, key: role)
      end

      def load_scalars(section)
        @source = section['source']
        callback = mapping(section['callback'], noun(:platform_map, key: 'callback'),
                           "#{@at}.callback", required: false)
        @callback_body = optional_text(callback, 'body', "#{@at}.callback")
        @callback_headers = optional_text(callback, 'headers', "#{@at}.callback")
        result = mapping(section['result'], noun(:platform_map, key: 'result'), "#{@at}.result",
                         required: false)
        @success_predicate = optional_text(result, 'success_predicate', "#{@at}.result")
      end

      def optional_text(table, key, at)
        return nil unless table.key?(key)

        text(table[key], noun(:expression, key: key), "#{at}.#{key}")
      end

      def complain(message, at)
        @problems.add(message, file: @file, path: at)
      end
    end
  end
end
