# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Композиции JSON Schema, приведённые к одному объекту до анализа.
    #
    # Отдельная стадия, а не заплата по месту вызова: и SchemaIndex, и
    # SchemaReader, и матчеры обязаны видеть одну и ту же каноническую схему,
    # иначе поле, спрятанное за `allOf`, есть в одном месте конвейера и
    # отсутствует в другом. Правила взяты у опубликованного OpenAPI
    # Normalizer из openapi-generator (`REFACTOR_ALLOF_WITH_PROPERTIES_ONLY`,
    # `SIMPLIFY_ONEOF_ANYOF`) и у `flatten` из oasdiff.
    #
    #   allOf         сумма: ветки сливаются в одну схему, `required`
    #                 объединяется, вложенная композиция разворачивается тоже
    #   oneOf/anyOf   выбор: ветка `null` отбрасывается; осталась одна — схема
    #                 ею и становится; осталось несколько — этим занимается
    #                 SchemaVariants
    #   discriminator читается там же и даёт условную обязательность уровня 1
    #
    # Ничего не мутирует: один и тот же узел документа нормализуют несколько
    # читателей, и правка на месте испортила бы соседу вход.
    class SchemaNormalizer
      # Замечание нормализации; место в документе добавит вызывающий.
      Remark = Struct.new(:code, :message, :severity, keyword_init: true)

      # Что дала нормализация.
      #
      #   node        схема без allOf/oneOf/anyOf
      #   remarks     [Remark] для записи анализатором
      #   variants    имя свойства => имя варианта, из которого оно пришло
      #   conditions  имя свойства => IR::RequiredWhen, прочитанное из
      #               `discriminator`
      Result = Struct.new(:node, :remarks, :variants, :conditions, keyword_init: true)

      SUM = 'allOf'
      CHOICE = %w[oneOf anyOf].freeze
      # Ключи, которые ветка наружу не отдаёт: композиции разбираются
      # отдельно, `properties` и `required` сливаются по своим правилам, а
      # маркер компонента принадлежит самому компоненту, а не сумме с ним.
      PRIVATE = ([SUM, 'properties', 'required', 'discriminator',
                  SchemaNaming::MARKER] + CHOICE).freeze
      # Глубже композиции не встречаются даже у Checkout.com; предел держит
      # рекурсию конечной на любом входе, включая разомкнутый цикл `$ref`.
      MAX_DEPTH = 8
      NULL = 'null'
      OBJECT = 'object'

      # @param node [Object] объект схемы, `$ref` уже разрешены
      # @param depth [Integer] глубина вложенности композиций
      # @return [Result]
      def self.call(node, depth: 0)
        new(node, depth: depth).call
      end

      # Свободная карта: объект, ключи которого спецификация не перечисляет
      # (`additionalProperties`, `patternProperties` или объект вовсе без
      # `properties`). Такое поле — хеш, а не скаляр, и это единственное, что
      # о нём известно.
      # @param node [Object]
      # @return [Boolean]
      def self.free_form?(node)
        return false unless node.is_a?(Hash)
        return false if node['properties'].is_a?(Hash) && !node['properties'].empty?
        return true if node['patternProperties'].is_a?(Hash)
        return true if node.key?('additionalProperties') && node['additionalProperties'] != false

        ConstraintReader.type_of(node).first == OBJECT
      end

      # @param node [Object]
      # @param depth [Integer]
      def initialize(node, depth: 0)
        @source = node.is_a?(Hash) ? node : {}
        @depth = depth
        @remarks = []
        @variants = {}
        @conditions = {}
      end

      # @return [Result]
      def call
        return result(@source) if too_deep?

        merged = CHOICE.reduce(sum(@source)) { |node, keyword| choice(node, keyword) }
        result(merged)
      end

      private

      def result(node)
        Result.new(node: node, remarks: @remarks, variants: @variants,
                   conditions: @conditions)
      end

      def too_deep?
        return false if @depth <= MAX_DEPTH

        remark(:spec_element_unsupported,
               Texts.t('analyzers.schema.composition_too_deep', limit: MAX_DEPTH), :info)
        true
      end

      # Сумма веток. Ветка нормализуется своей рекурсией, поэтому `allOf`
      # внутри `allOf` разворачивается, а не приносит ноль свойств.
      def sum(node)
        branches = node[SUM]
        return node unless branches.is_a?(Array)

        branches.grep(Hash).reduce(node.except(SUM)) do |merged, branch|
          absorb(merged, normalized(branch))
        end
      end

      # Выбор. Ветка `null` — это `nullable`, а не вариант: после неё чаще
      # всего остаётся ровно одна схема, и поле перестаёт быть невидимым.
      def choice(node, keyword)
        listed = node[keyword]
        return node unless listed.is_a?(Array) && !listed.empty?

        found = listed.grep(Hash).map { |branch| normalized(branch) }
        decide(node.except(keyword), found, found.reject { |branch| null?(branch.node) }, keyword)
      end

      def decide(rest, found, kept, keyword)
        rest = rest.merge('nullable' => true) if kept.size < found.size
        return rest if kept.empty?
        return absorb(rest, kept.first) if kept.size == 1

        spread(rest, kept, keyword)
      end

      # @return [Result]
      def normalized(branch)
        found = SchemaNormalizer.call(branch, depth: @depth + 1)
        @remarks.concat(found.remarks)
        found
      end

      # Ветка вносит в схему всё, чего в схеме ещё нет: внешнее написание
      # сильнее, потому что оно уточняет ветку, а не наоборот.
      def absorb(merged, found)
        adopt(found)
        branch = found.node
        result = branch.except(*PRIVATE).merge(merged)
        fill(result, 'properties', properties(merged, branch))
        fill(result, 'required', list(merged['required']) | list(branch['required']))
        result
      end

      def spread(node, kept, keyword)
        found = SchemaVariants.new(node: node, branches: kept.map(&:node), keyword: keyword)
        @remarks.concat(found.remarks)
        adopt(found)
        found.node
      end

      def adopt(found)
        @variants.merge!(found.variants) { |_, first, _| first }
        @conditions.merge!(found.conditions) { |_, first, _| first }
      end

      # Ключ появляется только тогда, когда есть что записать: пустой
      # `properties` у скалярной схемы читался бы как объект без свойств.
      def fill(node, key, value)
        return if value.empty? && !node.key?(key)

        node[key] = value
      end

      def properties(merged, branch)
        kept = merged['properties'].is_a?(Hash) ? merged['properties'].dup : {}
        listed = branch['properties']
        return kept unless listed.is_a?(Hash)

        listed.each do |name, schema|
          note_conflict(kept[name.to_s], schema, name.to_s)
          kept[name.to_s] ||= schema
        end
        kept
      end

      # Одно свойство описано в двух ветках по-разному. Остаётся первое —
      # но молча выбирать нельзя: вторая ветка могла требовать другого.
      def note_conflict(kept, incoming, name)
        return if kept.nil? || kept == incoming

        types = [type_of(kept), type_of(incoming)]
        return note_type_conflict(name, types) if types.uniq.size > 1 && types.none?(&:nil?)

        remark(:spec_element_unsupported,
               Texts.t('analyzers.schema.allof_property_conflict', name: name), :info)
      end

      def note_type_conflict(name, types)
        remark(:spec_element_unsupported,
               Texts.t('analyzers.schema.allof_type_conflict', name: name,
                                                               kept: types.first,
                                                               incoming: types.last),
               :warning)
      end

      def null?(node)
        return true if node['type'] == NULL || Array(node['type']) == [NULL]

        node['enum'] == [nil]
      end

      def type_of(node)
        return nil unless node.is_a?(Hash)

        ConstraintReader.type_of(node).first
      end

      def list(value)
        value.is_a?(Array) ? value.grep(String) : []
      end

      def remark(code, message, severity)
        @remarks << Remark.new(code: code, message: message, severity: severity)
      end
    end
  end
end
