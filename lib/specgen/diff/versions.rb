# frozen_string_literal: true

module SpecGen
  module Diff
    # Две версии одной спецификации: тот же загрузчик и те же анализаторы,
    # что и у генерации, а на выходе — список отличий.
    #
    # Само сравнение принимает готовые профили и о файлах не знает ничего.
    # Этот объект — мост между ним и вызывающим: он держит вместе пути,
    # overlay каждой версии и подписи файлов для заголовка отчёта, чтобы ни
    # CLI, ни веб не собирали профиль дважды одинаковым кодом. Overlay у
    # версий разный, потому что разные и спецификации: цели адресуют схемы
    # конкретного файла.
    #
    # Отсутствующий файл, битый YAML и документ не-OpenAPI остаются заботой
    # SpecLoader: он уже отвечает на них SpecGen::Error с именем файла и
    # местом ошибки, и вторая проверка здесь только повторила бы сообщение
    # своими словами.
    class Versions
      # @param options [Hash] опции запуска: `old`, `new`, необязательные
      #   `overlay_old` и `overlay_new`; их же читают анализаторы
      # @param rules [Rules::Registry] справочники
      def initialize(options, rules:)
        @options = options
        @rules = rules
      end

      # @return [Array<Change>] отличия, отсортированные Diff.call; считаются
      #   один раз, потому что вызывающему они нужны и для отчёта, и для кода
      #   выхода
      def changes
        @changes ||= Diff.call(profile(:old, :overlay_old), profile(:new, :overlay_new))
      end

      # Подпись версии называет и overlay: без него заголовок сравнения
      # спецификации с ней же самой читался бы как «файл отличается от себя».
      # @return [Hash{Symbol => String}] имена файлов для заголовка отчёта
      def labels
        { old: label(:old, :overlay_old), new: label(:new, :overlay_new) }
      end

      private

      def label(spec, overlay)
        [@options[spec], @options[overlay]].compact.map { |file| File.basename(file) }.join(' + ')
      end

      def profile(spec, overlay)
        document = SpecLoader.load(@options[spec], overlay: @options[overlay])
        Analyzers::Runner.call(document: document, rules: @rules, options: @options)
      end
    end
  end
end
