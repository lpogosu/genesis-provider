# frozen_string_literal: true

module SpecGen
  module Web
    # Каталог спецификаций для демонстрации в один клик: те же файлы, что
    # видит пакетный прогон, плюс заголовок и версия OpenAPI из каждого.
    #
    # Список файлов берётся у Batch#specs, а не собирается заново: /api/specs
    # и /api/batch обязаны показывать один и тот же набор. Заголовок читает
    # SpecLoader::Reader — тот же разбор YAML и JSON, что у загрузчика, но
    # без разрешения `$ref` и без проверки структуры: строка списка не
    # должна стоить полного разбора.
    #
    # Файл, который не читается, из списка не исчезает: строка остаётся с
    # пустым заголовком. Список — это то, что лежит в каталоге, а не то, что
    # удалось разобрать.
    class Catalog
      # @param dir [String] каталог со спецификациями
      # @param rules [Rules::Registry] справочники для Batch
      def initialize(dir:, rules:)
        @dir = dir
        @rules = rules
      end

      # @return [Hash] тело ответа /api/specs
      def to_h
        { specs: files.map { |file| entry(file) } }
      end

      # @param id [String] имя файла без расширения
      # @return [String] путь к файлу спецификации
      # @raise [RequestError] такого имени в каталоге нет
      def path(id)
        file = files.find { |candidate| identifier(candidate) == id }
        raise RequestError.new(:spec_unknown, file: id) if file.nil?

        file
      end

      private

      attr_reader :dir, :rules

      def files
        @files ||= Batch.new(dir: dir, rules: rules).specs
      end

      def entry(file)
        head = head(file)
        { id: identifier(file), file: relative(file), title: head&.dig('info', 'title'),
          openapi: head&.fetch('openapi', nil), bytes: File.size(file), own: own?(file) }
      end

      # @return [Hash, nil] разобранный документ или nil, если не читается
      def head(file)
        SpecLoader::Reader.read(file)
      rescue SpecGen::Error
        nil
      end

      def identifier(file)
        File.basename(file, File.extname(file))
      end

      # Свои спецификации лежат в корне каталога, чужие настоящие — в
      # подкаталоге. Признак структурный: имя подкаталога знать не нужно.
      def own?(file)
        !relative(file).include?('/')
      end

      def relative(file)
        path = slashes(file.delete_prefix(dir.to_s)).delete_prefix('/')
        path.empty? ? File.basename(file) : path
      end

      # Наружу путь уходит с прямыми разделителями на любой файловой
      # системе: фронт сравнивает его со строкой таблицы пакетного прогона.
      def slashes(path)
        File::ALT_SEPARATOR ? path.tr(File::ALT_SEPARATOR, '/') : path
      end
    end
  end
end
