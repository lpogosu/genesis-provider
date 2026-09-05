# frozen_string_literal: true

require 'psych'

module SpecGen
  # Тексты для человека на выбранном языке: сообщения CLI, метки отчёта,
  # формулировки предупреждений и обоснований.
  #
  # Зачем отдельный слой. Всё, что читает человек, — по-русски (эксперты и
  # жюри читают по-русски), всё, что читает машина, — по-английски. Но
  # инструмент не должен быть привязан к одному языку сильнее, чем к одному
  # провайдеру: новый язык — это новый каталог `locales/<код>/`, а не правка
  # кода. Файлы внутри каталога делятся по стадиям конвейера, чтобы две
  # стадии не редактировали один файл.
  #
  # Язык выбирается флагом `--locale`, переменной окружения SPECGEN_LOCALE
  # или по умолчанию — русский. Отсутствующий ключ или пропущенный параметр
  # подстановки — ошибка программиста, а не пользователя: она поднимается
  # как LocaleError, а тест на полноту локалей ловит её до запуска.
  module Texts
    DEFAULT = 'ru'
    ENV_VAR = 'SPECGEN_LOCALE'

    # Формы множественного числа по языкам. Русский различает «1 операция»,
    # «2 операции», «5 операций»; английский — только one и other.
    PLURAL_RULES = {
      'ru' => lambda do |number|
        n = number.abs
        next :many if (11..14).cover?(n % 100)

        case n % 10
        when 1 then :one
        when 2..4 then :few
        else :many
        end
      end,
      'en' => ->(number) { number.abs == 1 ? :one : :other }
    }.freeze

    class << self
      # @return [String] код текущего языка
      def locale
        @locale || ENV.fetch(ENV_VAR, DEFAULT)
      end

      # @param value [String, nil] код языка; nil возвращает выбор по
      #   умолчанию (переменная окружения, иначе русский)
      # @raise [LocaleError] если такого каталога локали нет
      def locale=(value)
        code = value.to_s
        @locale = code.empty? ? nil : checked(code)
      end

      # @return [Array<String>] коды языков, для которых есть каталог
      def supported
        Dir.children(SpecGen::LOCALES_DIR).select do |name|
          File.directory?(File.join(SpecGen::LOCALES_DIR, name))
        end.sort
      end

      # @param key [String] ключ вида "summary.provider"
      # @param params [Hash{Symbol => Object}] подстановки для %{имя}
      # @return [String]
      # @raise [LocaleError] нет ключа или не хватает параметра
      def t(key, **params)
        template = table(locale).fetch(key) do
          raise LocaleError, "в локали #{locale} нет ключа #{key.inspect}"
        end
        # format() всегда, даже без параметров: так шаблон с %{именем}, для
        # которого забыли значение, падает здесь, а не печатается как есть.
        # Литеральный процент в тексте локали пишется как %%.
        format(template, **params)
      rescue KeyError, ArgumentError => e
        raise LocaleError, "ключ #{key.inspect} в локали #{locale}: #{e.message}"
      end

      # @param key [String] ключ вида "generators.report.action_units_unknown"
      # @return [Boolean] есть ли такой ключ в текущей локали; нужен там, где
      #   текст пишется под открытый словарь (коды предупреждений) и
      #   отсутствие строки не должно останавливать генерацию
      def key?(key)
        table(locale).key?(key)
      end

      # @param number [Integer]
      # @param key [String] ключ существительного под `plural.`
      # @return [String] "5 операций", "1 schema"
      def plural(number, key)
        form = PLURAL_RULES.fetch(locale).call(number)
        "#{number} #{t("plural.#{key}.#{form}")}"
      end

      # @param code [String] код языка
      # @return [Array<String>] все ключи локали, отсортированные
      def keys(code)
        table(code).keys.sort
      end

      # Сбрасывает кеш прочитанных файлов; нужен тестам, которые правят
      # локали во временном каталоге.
      # @return [void]
      def reset!
        @tables = nil
        @locale = nil
      end

      private

      def checked(code)
        return code if supported.include?(code)

        raise LocaleError, "язык #{code.inspect} не поддерживается " \
                           "(доступны: #{supported.join(', ')})"
      end

      def table(code)
        (@tables ||= {})[code] ||= load(code)
      end

      def load(code)
        dir = File.join(SpecGen::LOCALES_DIR, code)
        raise LocaleError, "нет каталога локали #{dir}" unless File.directory?(dir)

        Dir.glob(File.join(dir, '*.yml')).each_with_object({}) do |file, table|
          flatten(Psych.safe_load_file(file) || {}, [], table, file)
        end
      end

      # Вложенные хеши YAML → плоские ключи через точку. Один ключ в двух
      # файлах — ошибка: иначе порядок чтения решал бы, какой текст победит.
      def flatten(node, path, table, file)
        node.each do |key, value|
          keys = path + [key.to_s]
          next flatten(value, keys, table, file) if value.is_a?(Hash)

          full = keys.join('.')
          raise LocaleError, "ключ #{full.inspect} задан дважды, второй раз в #{file}" if
            table.key?(full)

          table[full] = value.to_s
        end
      end
    end
  end
end
