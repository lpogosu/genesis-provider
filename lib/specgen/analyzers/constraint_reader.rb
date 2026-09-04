# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Ключевые слова валидации JSON Schema в том виде, в каком их хранит
    # IR::Field.
    #
    # Два написания обязаны свестись к одному, потому что сгенерированному
    # сервису всё равно, на каком диалекте писал провайдер:
    #
    #   nullable   OAS 3.0 пишет `nullable: true`; JSON Schema 2020-12
    #              (OAS 3.1) пишет `type: ["string", "null"]`
    #   exclusive  OAS 3.0 пишет `exclusiveMinimum: true` как модификатор к
    #              `minimum`; 2020-12 пишет `exclusiveMinimum: 100`
    #              самостоятельным ограничением. Храним по-2020-12 — числом,
    #              чтобы шаблон рисовал одно сравнение, а не два.
    module ConstraintReader
      # Ключевое слово спецификации => ключ из IR::Field::CONSTRAINT_KEYS.
      KEYS = {
        'enum' => :enum, 'const' => :const, 'pattern' => :pattern, 'minimum' => :minimum,
        'maximum' => :maximum, 'minLength' => :min_length, 'maxLength' => :max_length,
        'minItems' => :min_items, 'maxItems' => :max_items, 'multipleOf' => :multiple_of,
        'default' => :default
      }.freeze
      # Ключевое слово => [что задаёт, что заменяет, когда задано булевым].
      EXCLUSIVE = {
        'exclusiveMinimum' => %i[exclusive_minimum minimum],
        'exclusiveMaximum' => %i[exclusive_maximum maximum]
      }.freeze
      NULL = 'null'

      # @param node [Hash] объект схемы
      # @return [Array(String, Boolean)] тип в том виде, в каком его держит
      #   IR, и разрешён ли null
      def self.type_of(node)
        declared = node['type']
        nullable = node['nullable'] == true
        return [declared, nullable] unless declared.is_a?(Array)

        listed = declared.grep(String)
        [listed.reject { |type| type == NULL }.first, nullable || listed.include?(NULL)]
      end

      # @param node [Hash] объект схемы
      # @param nullable [Boolean] как его вернул #type_of
      # @return [Hash{Symbol => Object}] ключи из IR::Field::CONSTRAINT_KEYS
      def self.call(node, nullable: false)
        constraints = KEYS.filter_map { |keyword, key| [key, node[keyword]] if node.key?(keyword) }
                          .to_h
        constraints[:nullable] = true if nullable
        exclusives(node, constraints)
      end

      # @param node [Hash]
      # @param constraints [Hash]
      # @return [Hash] те же ограничения, но оба диалекта сведены к одному
      def self.exclusives(node, constraints)
        EXCLUSIVE.each do |keyword, (key, replaces)|
          value = node[keyword]
          next unless node.key?(keyword)

          constraints[key] = value if value.is_a?(Numeric)
          constraints[key] = constraints.delete(replaces) if value == true && constraints[replaces]
        end
        constraints
      end
    end
  end
end
