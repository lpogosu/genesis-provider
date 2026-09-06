# frozen_string_literal: true

module SpecGen
  module Generators
    # Прогоняет все генераторы по одному профилю и возвращает записанные
    # артефакты. Добавить артефакт — добавить класс в ORDER и шаблон в
    # templates/; больше ничего.
    class Runner
      # Порядок фиксирован: report.md идёт последним, потому что перечисляет
      # уже записанные артефакты с числом строк. Заготовка overlay стоит
      # перед ним по той же причине — попав в список, она видна там же, где
      # сказано, из чего собран сервис.
      ORDER = [ServiceGenerator, IntegrationGenerator, FixturesGenerator,
               OverlayGenerator, ReportGenerator].freeze
      DEFAULT_OUTPUT = 'output'

      # @param profile [IR::ProviderProfile]
      # @param rules [Rules::Registry]
      # @param document [SpecLoader::Document] спецификация, из которой
      #   выведен профиль; нужна стадии проверки, чтобы сверить записанные
      #   фикстуры со схемами той же спецификации
      # @param options [Hash] опции CLI, ключи строками или символами
      def initialize(profile:, rules:, document: nil, options: {})
        @profile = profile
        @rules = rules
        @document = document
        @options = options
      end

      # Каждый следующий генератор видит уже записанные артефакты: отчёту
      # нужен их список с числом строк, и брать его неоткуда, кроме прогона.
      # @return [Array<Artifact>] в порядке ORDER
      # @raise [GenerationError]
      def call
        naming = Naming.for(@profile)
        writer = Writer.new(output_dir)
        enabled.each_with_object([]) do |generator, artifacts|
          artifacts << generator.new(profile: @profile, rules: @rules, options: @options,
                                     naming: naming, writer: writer,
                                     artifacts: artifacts.dup, checks: checks(artifacts)).call
        end
      end

      # Артефакт, который просили. Решает сам генератор: спрашивать у
      # Runner, какой флаг что включает, значило бы держать список флагов в
      # двух местах.
      # @return [Array<Class>] подмножество ORDER в том же порядке
      def enabled
        ORDER.select { |generator| generator.enabled?(@options) }
      end

      # Сверка фикстур со схемами спецификации. Считается один раз, сразу
      # после того, как фикстуры записаны: проверяется файл на диске, а не
      # то, что генератор держал в памяти. До этого момента проверять нечего,
      # и стадия возвращает nil.
      # @param artifacts [Array<Artifact>] уже записанное
      # @return [Validators::Result, nil]
      def checks(artifacts)
        fixtures = artifacts.find { |artifact| artifact.kind == FixturesGenerator::KIND }
        return nil if fixtures.nil?

        @checks ||= Validators.check(document: @document, profile: @profile,
                                     fixtures_file: fixtures.path)
      end

      # @return [String] каталог вывода из --output, иначе DEFAULT_OUTPUT
      def output_dir
        value = @options[:output] || @options['output']
        value.nil? || value.to_s.empty? ? DEFAULT_OUTPUT : value.to_s
      end
    end
  end
end
