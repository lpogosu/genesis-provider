# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Что ветка `else` схемы говорит об одном поле.
    #
    # Отрицание превращается в равенство ровно в одном случае: у
    # поля-триггера объявлен enum ровно из двух значений и ветка `if`
    # проверяет одно из них. Тогда «иначе» называет второе однозначно — это
    # арифметика по формальной структуре спецификации, а не чтение прозы,
    # поэтому вывод такой же надёжный, как сама ветка `then`.
    #
    # Уже при трёх значениях «не первое» не называет ни одного из двух
    # оставшихся, а IR хранит равенство, а не отрицание: там #value пуст, и
    # вызывающий предупреждает. Отсутствие enum — тот же случай.
    class NegatedBranch
      # @return [String, nil] имя соседнего поля, на которое смотрит `if`
      attr_reader :trigger
      # @return [Object, nil] единственное значение, которое `if` проверяет
      attr_reader :tested
      # @return [Array] значения, объявленные соседу самой схемой
      attr_reader :enum

      # @param parent [Hash] схема, которой принадлежит поле
      # @param keys [ConditionReader::Keywords] написание тройки ключевых слов
      # @param name [String] имя поля, чью обязательность проверяем
      def initialize(parent, keys, name)
        @parent = parent
        @keys = keys
        @declared = required?(otherwise, name)
        @trigger, @tested = single_value(parent[keys.if_key])
        @enum = @trigger.nil? ? [] : enum_of(@trigger)
      end

      # @return [Boolean] ветка `else` объявляет это поле обязательным
      def declared?
        @declared
      end

      # @return [Object, nil] значение соседа, которое остаётся ветке `else`
      def value
        return nil unless declared? && enum.size == 2 && enum.include?(tested)

        (enum - [tested]).first
      end

      # @return [Boolean] `if` проверяет значение, которого схема соседу не
      #   объявляла: спецификация противоречит сама себе
      def off_enum?
        declared? && !enum.empty? && !enum.include?(tested)
      end

      # @return [String] enum соседа одной строкой, для сообщений
      def listed
        enum.join(' | ')
      end

      private

      attr_reader :parent, :keys

      # Ветка «иначе» пишется рядом с `if` (так велит реестр расширений
      # OpenAPI для 3.0) или внутри него (так велит родная JSON Schema).
      def otherwise
        beside = parent[keys.else_key]
        return beside if beside.is_a?(Hash)

        test = parent[keys.if_key]
        test.is_a?(Hash) ? test['else'] : nil
      end

      # @return [Array(String, Object)] имя соседа и значение; [nil, nil],
      #   когда `if` не называет ровно одного значения
      def single_value(test)
        return [nil, nil] unless test.is_a?(Hash) && test['properties'].is_a?(Hash)

        name, body = test['properties'].find { |_, node| node.is_a?(Hash) }
        return [nil, nil] if name.nil?

        listed = body.key?('const') ? [body['const']] : Array(body['enum'])
        listed.size == 1 ? [name.to_s, listed.first] : [nil, nil]
      end

      # @return [Array] enum соседнего поля; пусто, когда его нет
      def enum_of(name)
        properties = parent['properties']
        node = properties.is_a?(Hash) ? properties[name] : nil
        listed = node.is_a?(Hash) ? node['enum'] : nil
        listed.is_a?(Array) ? listed : []
      end

      def required?(node, name)
        node.is_a?(Hash) && node['required'].is_a?(Array) && node['required'].include?(name)
      end
    end
  end
end
