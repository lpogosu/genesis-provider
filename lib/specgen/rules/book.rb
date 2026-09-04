# frozen_string_literal: true

module SpecGen
  module Rules
    # Один файл справочника из rules/. Книга сверяет свой файл с закрытыми
    # наборами IR::Roles и объектов IR, а затем отдаёт его как те выборки,
    # которые вызывают анализаторы и генераторы. Проблемы уходят в общий
    # сборщик, а не поднимаются сразу: одна загрузка сообщает обо всех
    # промахах во всех справочниках, после чего отказывается отдать
    # полувалидный реестр.
    #
    # Наследник объявляет FILE и реализует #build.
    class Book
      include Checks

      SUPPORTED_VERSION = 1

      # @return [String] путь файла, из которого прочитана книга
      attr_reader :file

      # @param document [Document] уже разобранный справочник
      # @param problems [Problems] общий сборщик проблем
      def initialize(document, problems)
        @file = document.file
        @data = document.data
        @problems = problems
        check_version
        build
      end

      # @return [String] имя файла — так справочник называют сообщения
      def name
        File.basename(file)
      end

      private

      attr_reader :data, :problems

      # Заполняет выборки из `data`. Наследники переопределяют.
      # @return [void]
      def build; end

      def check_version
        version = data['version']
        return if version == SUPPORTED_VERSION

        fault('book.version', path('version'), expected: SUPPORTED_VERSION,
                                               got: describe(version))
      end

      # @param key [String] имя раздела верхнего уровня
      # @param type [Class] Hash или Array
      # @param required [Boolean] считать ли отсутствие раздела проблемой
      # @return [Hash, Array] сам раздел или пустой раздел нужного типа
      def section(key, type = Hash, required: true)
        value = data[key]
        return value if value.is_a?(type)
        return type.new if value.nil? && !required

        expected = SpecLoader::TypeName::NAMES.fetch(type)
        fault('book.section', path(key), expected: expected, got: describe(value))
        type.new
      end

      def path(*keys)
        SpecLoader::JsonPath.build(keys)
      end

      def complain(message, at)
        problems.add(message, file: file, path: at)
      end
    end
  end
end
