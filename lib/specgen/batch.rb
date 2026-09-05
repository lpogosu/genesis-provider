# frozen_string_literal: true

module SpecGen
  # Пакетный прогон: каталог со спецификациями на входе, по комплекту
  # артефактов на каждую и одна сводная таблица на выходе.
  #
  # Зачем это есть. Эксперты кейса на чекпоинте 2 (5 сентября 2026) сказали
  # прямо, что проверять будут на чужих OpenAPI-файлах и что важнее всего
  # уметь их разбирать. Отдельный прогон на каждую спецификацию это доказать
  # не может: нужна одна команда, после которой видно, что инструмент прошёл
  # по семи чужим файлам и на каждом что-то извлёк.
  #
  # Спецификация, которую загрузчик отверг, останавливает только себя: строка
  # таблицы получает сообщение об ошибке, остальные продолжают. Это тоже
  # часть ответа — генератор не падает на чужом входе.
  #
  # Каталог вывода на каждую спецификацию свой (`<output>/<slug>/`), иначе
  # вторая перезаписала бы артефакты первой.
  class Batch
    # Расширения, которые вообще имеет смысл пробовать открыть.
    EXTENSIONS = %w[.yaml .yml .json].freeze
    # Каталог по умолчанию: наши спецификации и настоящие публичные рядом.
    DEFAULT_DIR = 'spec/fixtures/specs'

    # Результат одной спецификации: либо числа, либо сообщение об ошибке.
    #
    #   file        путь спецификации относительно каталога прогона
    #   provider    slug провайдера, он же подкаталог вывода
    #   operations  сколько операций найдено
    #   roles       у скольких из них выведена роль
    #   coverage    покрытие спецификации в процентах
    #   warnings    сколько предупреждений собрал профиль
    #   artifacts   сколько файлов записано
    #   error       сообщение, если прогон не дошёл до конца
    Row = Struct.new(:file, :provider, :operations, :roles, :coverage, :warnings, :artifacts,
                     :error, keyword_init: true) do
      # @return [Boolean]
      def ok?
        error.nil?
      end
    end

    # @param dir [String] каталог со спецификациями, обходится рекурсивно
    # @param rules [Rules::Registry] уже загруженные справочники
    # @param options [Hash] опции CLI: из них берётся каталог вывода
    def initialize(dir:, rules:, options: {})
      @dir = dir
      @rules = rules
      @options = options
    end

    # @return [Array<Row>] по строке на спецификацию, в порядке файлов
    # @raise [SpecLoadError] каталога нет или в нём нечего разбирать
    def call
      files = specs
      raise SpecLoadError.new(Texts.t('cli.batch_empty'), file: @dir) if files.empty?

      files.map { |file| row(file) }
    end

    # @return [Array<String>] спецификации каталога в детерминированном порядке
    def specs
      return [] unless File.directory?(@dir)

      Dir.glob(File.join(@dir, '**', '*')).select do |path|
        File.file?(path) && EXTENSIONS.include?(File.extname(path).downcase)
      end.sort
    end

    private

    def row(file)
      profile, artifacts = run(file)
      report = artifacts.find { |artifact| artifact.kind == :report }
      Row.new(file: relative(file), provider: Generators::Naming.for(profile).slug,
              operations: profile.operations.size, roles: mapped(profile),
              coverage: report&.metrics&.fetch(:coverage_percent, nil),
              warnings: profile.warnings.size, artifacts: artifacts.size)
    rescue SpecGen::Error => e
      Row.new(file: relative(file), error: e.message)
    end

    # Имя провайдера берётся из имени файла, а не из заголовка
    # спецификации: в пакетном прогоне важно, чтобы строка таблицы, каталог
    # вывода и имя класса читались как один и тот же провайдер. Заголовки у
    # чужих спек бывают безымянные («Payouts API»), и два разных провайдера
    # получили бы один slug.
    def run(file)
      options = @options.merge(spec: file, output: output_for(file), provider: name_of(file))
      document = SpecLoader.load(file)
      profile = Analyzers::Runner.call(document: document, rules: @rules, options: options)
      [profile, Generators.call(profile: profile, rules: @rules, options: options)]
    end

    # Подкаталог вывода по имени файла, а не по провайдеру: имя провайдера
    # известно только после разбора, а каталог нужен раньше.
    def output_for(file)
      File.join(base_output, name_of(file))
    end

    def name_of(file)
      File.basename(file, File.extname(file))
    end

    def base_output
      value = @options[:output] || @options['output']
      value.nil? || value.to_s.empty? ? Generators::Runner::DEFAULT_OUTPUT : value.to_s
    end

    def mapped(profile)
      profile.operations.count { |operation| !operation.unmapped? }
    end

    def relative(file)
      path = file.delete_prefix(@dir.to_s).sub(%r{\A[/\\]}, '')
      path.empty? ? File.basename(file) : path
    end
  end
end
