# frozen_string_literal: true

require 'psych'

module SpecGen
  module Rules
    # Читает один файл справочника в Hash со строковыми ключами. Всё, что
    # может быть не так с самим файлом — нет файла, не читается, битый
    # синтаксис, пустой, не объект, ключ объявлен дважды, — становится
    # RulesError с именем файла, а для ошибки синтаксиса ещё и со строкой и
    # столбцом.
    class Document
      # @return [String] путь, из которого прочитан справочник
      attr_reader :file
      # @return [Hash] разобранный документ со строковыми ключами
      attr_reader :data

      # @param path [String]
      # @return [Document]
      # @raise [RulesError]
      def self.read(path)
        new(path).read
      end

      # @param path [String]
      def initialize(path)
        @file = path
      end

      # @return [Document] сам объект с заполненным `data`
      # @raise [RulesError]
      def read
        text = read_text
        reject_duplicates(text)
        @data = parse(text)
        return self if @data.is_a?(Hash) && !@data.empty?

        fail_rules('not_object', '$', got: SpecLoader::TypeName.of(@data))
      end

      private

      def read_text
        File.read(file, mode: 'r:bom|utf-8')
      rescue Errno::ENOENT
        fail_rules('not_found')
      rescue Errno::EISDIR
        fail_rules('is_directory')
      rescue SystemCallError => e
        fail_rules('unreadable', nil, error: e.message)
      end

      def parse(text)
        Psych.safe_load(text, aliases: true, filename: file)
      rescue Psych::SyntaxError => e
        fail_rules('yaml_syntax', where(e), problem: e.problem)
      rescue Psych::Exception => e
        fail_rules('yaml_error', nil, error: e.message)
      end

      def reject_duplicates(text)
        duplicates = DuplicateKeys.find(text, file)
        return if duplicates.empty?

        listed = duplicates.map do |path, line|
          Texts.t('rules.document.duplicate_at', path: path, line: line)
        end
        fail_rules('duplicates', nil, keys: listed.join(', '))
      rescue Psych::SyntaxError => e
        fail_rules('yaml_syntax', where(e), problem: e.problem)
      end

      def where(error)
        Texts.t('rules.document.location', line: error.line, column: error.column)
      end

      def fail_rules(key, location = nil, **params)
        message = Texts.t("rules.document.#{key}", **params)
        raise RulesError.new(message, file: file, path: location)
      end
    end
  end
end
