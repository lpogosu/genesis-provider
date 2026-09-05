# frozen_string_literal: true

module SpecGen
  module Generators
    # Прогоняет все генераторы по одному профилю и возвращает записанные
    # артефакты. Добавить артефакт — добавить класс в ORDER и шаблон в
    # templates/; больше ничего.
    class Runner
      # Порядок фиксирован: report.md идёт последним, потому что перечисляет
      # уже записанные артефакты с числом строк.
      ORDER = [ServiceGenerator, IntegrationGenerator, FixturesGenerator, ReportGenerator].freeze
      DEFAULT_OUTPUT = 'output'

      # @param profile [IR::ProviderProfile]
      # @param rules [Rules::Registry]
      # @param options [Hash] опции CLI, ключи строками или символами
      def initialize(profile:, rules:, options: {})
        @profile = profile
        @rules = rules
        @options = options
      end

      # Каждый следующий генератор видит уже записанные артефакты: отчёту
      # нужен их список с числом строк, и брать его неоткуда, кроме прогона.
      # @return [Array<Artifact>] в порядке ORDER
      # @raise [GenerationError]
      def call
        naming = Naming.for(@profile)
        writer = Writer.new(output_dir)
        ORDER.each_with_object([]) do |generator, artifacts|
          artifacts << generator.new(profile: @profile, rules: @rules, options: @options,
                                     naming: naming, writer: writer,
                                     artifacts: artifacts.dup).call
        end
      end

      # @return [String] каталог вывода из --output, иначе DEFAULT_OUTPUT
      def output_dir
        value = @options[:output] || @options['output']
        value.nil? || value.to_s.empty? ? DEFAULT_OUTPUT : value.to_s
      end
    end
  end
end
