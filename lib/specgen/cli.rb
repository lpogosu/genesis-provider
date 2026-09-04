# frozen_string_literal: true

require 'thor'

module SpecGen
  # Точка входа командной строки за `./integrate`. Разбирает аргументы,
  # проверяет, что флаги согласованы между собой, и передаёт работу
  # конвейеру. Ничего не знает ни о спецификациях, ни о провайдерах.
  #
  # Язык сообщений выбирается флагом `--locale`, переменной окружения
  # SPECGEN_LOCALE или по умолчанию — русский. Тексты справки Thor читает
  # при загрузке класса, поэтому `--help` следует переменной окружения, а не
  # флагу: `SPECGEN_LOCALE=en ./integrate --help`.
  #
  # Коды выхода: 0 успех, 1 ошибка (или предупреждения при --strict),
  # 2 неверное использование.
  class CLI < Thor
    EXIT_ERROR = 1
    EXIT_USAGE = 2
    SUPPORTED_LANGS = %w[ruby].freeze

    package_name 'integrate'
    default_command :generate
    check_unknown_options!
    map %w[-v --version] => :version
    # В Thor 1.5 есть встроенная команда `tree`; в нашей справке она лишняя.
    remove_command :tree

    class_option :locale, type: :string, aliases: '-L', desc: Texts.t('cli.option.locale')

    # Thor просит объявить это явно; иначе ошибки аргументов выходят с кодом 0.
    def self.exit_on_failure?
      true
    end

    # Запуск CLI. Ошибки использования и ошибки генератора становятся одной
    # строкой в stderr с различимым кодом выхода; стектрейс пользователь не
    # видит никогда.
    def self.start(given_args = ARGV, config = {})
      shell = config[:shell] || Thor::Base.shell.new
      super(given_args, config.merge(shell: shell, debug: true))
    rescue Thor::Error => e
      shell.error("#{Texts.t('cli.usage_prefix')}: #{e.message}")
      exit(EXIT_USAGE)
    rescue SpecGen::Error => e
      shell.error("#{Texts.t('cli.error_prefix')}: #{e.message}")
      exit(EXIT_ERROR)
    end

    desc 'generate --spec FILE [options]', Texts.t('cli.desc.generate')
    long_desc Texts.t('cli.desc.generate_long')
    method_option :spec, type: :string, aliases: '-s', desc: Texts.t('cli.option.spec')
    method_option :provider, type: :string, aliases: '-p', desc: Texts.t('cli.option.provider')
    method_option :lang, type: :string, default: 'ruby', desc: Texts.t('cli.option.lang')
    method_option :overlay, type: :string, desc: Texts.t('cli.option.overlay')
    method_option :output, type: :string, default: 'output', aliases: '-o',
                           desc: Texts.t('cli.option.output')
    method_option :with_mock, type: :boolean, default: false, desc: Texts.t('cli.option.with_mock')
    method_option :fix, type: :boolean, default: false, desc: Texts.t('cli.option.fix')
    method_option :strict, type: :boolean, default: false, desc: Texts.t('cli.option.strict')
    method_option :all, type: :boolean, default: false, desc: Texts.t('cli.option.all')
    def generate
      apply_locale!
      validate_generate_options!
      # Падает здесь, до чтения спецификации, если что-то в rules/
      # противоречиво: синоним, заявленный двумя ролями, не должен дойти до
      # платёжного запроса, а ошибка при старте — самое дешёвое место сказать
      # об этом.
      Rules.load
      not_implemented('generate')
    end

    desc 'analyze --spec FILE [--provider NAME] [--explain]', Texts.t('cli.desc.analyze')
    long_desc Texts.t('cli.desc.analyze_long')
    method_option :spec, type: :string, aliases: '-s', required: true,
                         desc: Texts.t('cli.option.spec')
    method_option :provider, type: :string, aliases: '-p', desc: Texts.t('cli.option.provider')
    method_option :explain, type: :boolean, default: false, desc: Texts.t('cli.option.explain')
    def analyze
      apply_locale!
      raise SpecLoadError.new(Texts.t('cli.spec_not_found'), file: options[:spec]) if missing_spec?

      rules = Rules.load
      document = SpecLoader.load(options[:spec])
      profile = Analyzers::Runner.call(document: document, rules: rules, options: options)
      Reporter::Summary.new(profile, document, explain: options[:explain]).print_to($stdout)
    end

    desc 'diff', Texts.t('cli.desc.diff')
    method_option :old, type: :string, required: true, desc: Texts.t('cli.option.old')
    method_option :new, type: :string, required: true, desc: Texts.t('cli.option.new')
    def diff
      apply_locale!
      not_implemented('diff')
    end

    desc 'version', Texts.t('cli.desc.version')
    def version
      apply_locale!
      say Texts.t('cli.version', version: SpecGen::VERSION)
    end

    private

    # Флаг --locale действует на всё, что печатается после него; без флага
    # остаётся выбор по умолчанию (SPECGEN_LOCALE, иначе русский).
    def apply_locale!
      Texts.locale = options[:locale]
    rescue LocaleError
      raise Thor::Error, Texts.t('cli.unsupported_locale', locale: options[:locale],
                                                           supported: Texts.supported.join(', '))
    end

    def validate_generate_options!
      no_target = options[:spec].nil? && !options[:all]
      raise Thor::Error, Texts.t('cli.need_spec_or_all') if no_target
      raise SpecLoadError.new(Texts.t('cli.spec_not_found'), file: options[:spec]) if missing_spec?

      check_lang!
    end

    def check_lang!
      return if SUPPORTED_LANGS.include?(options[:lang])

      raise Thor::Error, Texts.t('cli.unsupported_lang', lang: options[:lang],
                                                         supported: SUPPORTED_LANGS.join(', '))
    end

    def missing_spec?
      options[:spec] && !File.file?(options[:spec])
    end

    def not_implemented(command)
      raise Error, Texts.t('cli.not_implemented', command: command, version: SpecGen::VERSION)
    end
  end
end
