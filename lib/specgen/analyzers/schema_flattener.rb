# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Сворачивает `allOf` в один объект схемы и сообщает о тех ключевых
    # словах композиции, которые мы не раскладываем.
    #
    # `allOf` — обычный способ сказать «эти поля плюс те»: потерять ветку
    # значит потерять обязательные поля из сгенерированного запроса, поэтому
    # ветки сливаются — сначала внешняя схема, затем каждая ветка по порядку,
    # а уже присутствующее свойство сохраняется, а не перезаписывается.
    #
    # `oneOf` и `anyOf` описывают варианты, а не сумму, и превращение их в
    # одну плоскую схему выдумало бы поля, которые провайдер никогда не
    # принимает вместе. Поэтому о них сообщается: отчёт говорит, какие
    # варианты есть и что выбрать обязан человек.
    module SchemaFlattener
      VARIANTS = %w[oneOf anyOf].freeze

      # @param node [Object] объект схемы
      # @return [Array(Hash, Array<Array(Symbol, String)>)] слитая схема и
      #   пары [код предупреждения, сообщение], чтобы вызывающий их записал
      def self.call(node)
        return [{}, []] unless node.is_a?(Hash)

        notes = []
        merged = merge(node, notes)
        VARIANTS.each { |keyword| note_variants(node, keyword, notes) }
        [merged, notes]
      end

      # @return [Hash]
      def self.merge(node, notes)
        branches = node['allOf']
        return node unless branches.is_a?(Array)

        merged = node.except('allOf')
        branches.grep(Hash).each { |branch| absorb(merged, branch, notes) }
        merged
      end

      # @return [void]
      def self.absorb(merged, branch, notes)
        merged['type'] ||= branch['type']
        merged['description'] ||= branch['description']
        merged['properties'] = merge_properties(merged, branch, notes)
        required = list(merged['required']) | list(branch['required'])
        merged['required'] = required unless required.empty?
      end

      # @return [Hash]
      def self.merge_properties(merged, branch, notes)
        properties = merged['properties'].is_a?(Hash) ? merged['properties'].dup : {}
        listed = branch['properties']
        return properties unless listed.is_a?(Hash)

        listed.each do |name, schema|
          note_conflict(properties[name], schema, name, notes)
          properties[name] ||= schema
        end
        properties
      end

      # @return [void]
      def self.note_conflict(kept, incoming, name, notes)
        return unless kept.is_a?(Hash) && incoming.is_a?(Hash)

        types = [kept['type'], incoming['type']]
        return if types.any?(&:nil?) || types.uniq.size == 1

        notes << [:spec_element_unsupported,
                  Texts.t('analyzers.schema.allof_type_conflict',
                          name: name, kept: types.first, incoming: types.last)]
      end

      # @return [void]
      def self.note_variants(node, keyword, notes)
        branches = node[keyword]
        return unless branches.is_a?(Array) && !branches.empty?

        notes << [:spec_element_unsupported,
                  Texts.t('analyzers.schema.variants_not_decomposed',
                          keyword: keyword, count: branches.size)]
      end

      # @return [Array<String>]
      def self.list(value)
        value.is_a?(Array) ? value.grep(String) : []
      end
    end
  end
end
