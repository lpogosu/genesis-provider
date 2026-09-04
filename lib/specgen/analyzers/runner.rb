# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Прогоняет все анализаторы по одному документу и возвращает
    # заполненный профиль.
    #
    # Порядок фиксирован только ради воспроизводимости: анализаторы
    # независимы по контракту и ни один не читает то, что записал другой,
    # поэтому при любом порядке результат был бы тем же. Список в одном
    # месте — то, что позволяет `integrate analyze` и конвейеру генерации
    # использовать ровно одну и ту же стадию анализа.
    class Runner
      ORDER = [InfoAnalyzer, AuthAnalyzer, OperationAnalyzer, SchemaAnalyzer].freeze

      # @param document [SpecLoader::Document] спецификация со всеми
      #   разрешёнными `$ref`
      # @param rules [Rules::Registry] справочники
      # @param options [Hash] опции CLI, ключи строками или символами
      # @return [IR::ProviderProfile] заполненный всеми анализаторами из ORDER
      def self.call(document:, rules:, options: {})
        profile = IR::ProviderProfile.new
        ORDER.each do |analyzer|
          analyzer.call(document: document, profile: profile, rules: rules, options: options)
        end
        profile
      end
    end
  end
end
