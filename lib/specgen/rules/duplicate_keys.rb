# frozen_string_literal: true

require 'psych'

module SpecGen
  module Rules
    # Ищет ключи, объявленные дважды внутри одного YAML-объекта. Psych молча
    # оставляет последнее значение, поэтому синоним, скопированный под две
    # роли, или валюта, перечисленная дважды с разными экспонентами,
    # загрузились бы без единой жалобы и работали бы неверно. В справочнике,
    # который ведут руками, это всегда ошибка, поэтому загрузчик отказывает
    # файлу, а не угадывает, какое из двух значений имели в виду.
    module DuplicateKeys
      # @param text [String] исходный YAML
      # @param file [String] путь; попадает в сообщения самого парсера
      # @return [Array<Array(String, Integer)>] JSONPath и строка каждого
      #   повторённого ключа, в порядке документа
      # @raise [Psych::SyntaxError] если файл вообще не разбирается
      def self.find(text, file)
        document = Psych.parse(text, filename: file)
        return [] unless document

        found = []
        walk(document.root, [], found)
        found
      end

      # @param node [Psych::Nodes::Node, nil]
      # @param keys [Array<String, Integer>] путь от корня документа
      # @param found [Array] накопитель
      # @return [void]
      def self.walk(node, keys, found)
        case node
        when Psych::Nodes::Mapping then walk_mapping(node, keys, found)
        when Psych::Nodes::Sequence
          node.children.each_with_index { |child, index| walk(child, keys + [index], found) }
        end
      end

      # @return [void]
      def self.walk_mapping(node, keys, found)
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          key = key_node.is_a?(Psych::Nodes::Scalar) ? key_node.value : nil
          next if key.nil?

          found << [SpecLoader::JsonPath.build(keys + [key]), key_node.start_line + 1] if seen[key]
          seen[key] = true
          walk(value_node, keys + [key], found)
        end
      end
    end
  end
end
