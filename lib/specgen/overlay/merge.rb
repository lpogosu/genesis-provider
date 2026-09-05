# frozen_string_literal: true

module SpecGen
  module Overlay
    # Слияние объекта `update` с целью действия.
    #
    # Правило — из описания Action Object спецификации Overlay 1.0.0:
    # свойства объекта `update` сливаются со свойствами цели, вложенные
    # объекты сливаются рекурсивно, любое другое значение (скаляр, массив)
    # заменяется целиком. Это не JSON Merge Patch (RFC 7386): `null` в
    # `update` присваивается свойству, а не удаляет его; удаление в Overlay
    # выражается отдельным действием `remove`.
    #
    # Попутно копится список переопределений: ключ, который в спецификации
    # уже был и значил другое, — это спор человека со спецификацией, и он
    # обязан быть виден. Ключ, которого не было, — дополнение, спорить не с
    # чем.
    class Merge
      # @param changes [Array<Result::Change>] накопитель переопределений
      def initialize(changes)
        @changes = changes
      end

      # @param node [Hash] узел спецификации; меняется на месте
      # @param update [Hash] объект из действия overlay
      # @param keys [Array<String, Integer>] путь узла от корня документа
      # @return [Hash] тот же узел
      def call(node, update, keys)
        update.each do |key, value|
          current = node[key]
          if current.is_a?(Hash) && value.is_a?(Hash)
            call(current, value, keys + [key])
          else
            record(keys + [key], current, value) if node.key?(key) && current != value
            node[key] = value
          end
        end
        node
      end

      private

      def record(keys, before, after)
        @changes << Result::Change.new(json_path: SpecLoader::JsonPath.build(keys),
                                       before: before, after: after)
      end
    end
  end
end
