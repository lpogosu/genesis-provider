# frozen_string_literal: true

module SpecGen
  module Overlay
    # Цель действия: выражение JSONPath и путь ключей, в который оно
    # разобрано.
    #
    # Поддерживается ровно то подмножество JSONPath, которое печатает наш же
    # отчёт (`SpecLoader::JsonPath`): корень, имя через точку, ключ в
    # скобках в кавычках, индекс массива. Этого хватает на все цели, которые
    # инструмент предлагает сам, — схема, свойство схемы, операция, ответ,
    # параметр по индексу, — а движок общего вида (`..`, `*`, фильтры) не
    # писан намеренно: цель, адресующая несколько узлов, сделала бы ответ на
    # вопрос «что именно переопределено» непроверяемым.
    class Target
      # Узла нет. Отдельный объект, потому что `nil` — законное значение
      # внутри документа, и «не найдено» обязано отличаться от «найдено nil».
      MISSING = Object.new.freeze

      # @return [String] выражение как его написал человек
      attr_reader :expression
      # @return [Array<String, Integer>] путь ключей от корня документа
      attr_reader :keys

      # @param expression [String]
      # @return [Target, nil] nil, если синтаксис вне подмножества
      def self.parse(expression)
        keys = SpecLoader::JsonPath.parse(expression)
        keys && new(expression, keys)
      end

      # @param expression [String]
      # @param keys [Array<String, Integer>]
      def initialize(expression, keys)
        @expression = expression.to_s
        @keys = keys.freeze
        freeze
      end

      # @return [Boolean] цель — весь документ
      def root?
        keys.empty?
      end

      # @param root [Hash] документ спецификации
      # @return [Object] узел цели либо MISSING
      def resolve(root)
        walk(root, keys)
      end

      # То, из чего узел придётся удалить: сам контейнер и ключ в нём.
      # @param root [Hash] документ спецификации
      # @return [Array(Object, Object), nil] nil для корня
      def container(root)
        return nil if root?

        parent = walk(root, keys[0..-2])
        MISSING.equal?(parent) ? nil : [parent, keys.last]
      end

      # @return [String]
      def to_s
        expression
      end

      private

      def walk(root, path)
        path.reduce(root) do |node, key|
          child = child(node, key)
          return MISSING if MISSING.equal?(child)

          child
        end
      end

      # Ключи документа нормализованы в строки загрузчиком, поэтому индекс из
      # `[0]` ищется в массиве по номеру, а в объекте — по строке: `[200]` и
      # `['200']` адресуют один и тот же ответ.
      def child(node, key)
        case node
        when Hash then node.key?(key.to_s) ? node[key.to_s] : MISSING
        when Array then key.is_a?(Integer) && key < node.size ? node[key] : MISSING
        else MISSING
        end
      end
    end
  end
end
