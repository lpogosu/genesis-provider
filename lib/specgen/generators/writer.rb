# frozen_string_literal: true

module SpecGen
  module Generators
    # Записывает артефакты в каталог вывода.
    #
    # Всегда в бинарном режиме: Ruby на Windows в текстовом режиме
    # подставляет CRLF, а golden-тесты сравнивают байты, и
    # `Layout/EndOfLine: lf` этого не переживёт. Каталог создаётся, если его
    # нет; файл заканчивается ровно одним переводом строки. Ошибка файловой
    # системы — нет прав, путь занят файлом — становится GenerationError с
    # путём, а не стектрейсом.
    class Writer
      # @return [String] каталог вывода
      attr_reader :dir

      # @param dir [String] каталог вывода; создаётся при первой записи
      def initialize(dir)
        @dir = dir
      end

      # @param name [String] имя файла внутри каталога
      # @param content [String] содержимое
      # @return [String] полный путь записанного файла
      # @raise [GenerationError]
      def write(name, content)
        path = File.join(dir, name)
        FileUtils.mkdir_p(dir)
        File.binwrite(path, normalize(content))
        path
      rescue SystemCallError => e
        raise GenerationError.new(Texts.t('generators.write_failed', error: e.message), file: path)
      end

      private

      # LF везде, без хвостовых пустых строк, один "\n" в конце.
      def normalize(content)
        "#{content.gsub("\r\n", "\n").sub(/\s*\z/, '')}\n"
      end
    end
  end
end
