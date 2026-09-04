# frozen_string_literal: true

require 'date'
require 'json'
require 'psych'

module SpecGen
  module SpecLoader
    # Читает один файл YAML или JSON в Hash со строковыми ключами. Каждый
    # способ оказаться непригодным — файла нет, по пути каталог, файл пуст,
    # битый синтаксис, в корне не объект — становится SpecLoadError, которая
    # называет файл, а для ошибок синтаксиса ещё строку и столбец.
    class Reader
      YAML_CLASSES = [Date, Time].freeze
      JSON_EXTENSIONS = %w[.json].freeze
      YAML_EXTENSIONS = %w[.yaml .yml].freeze
      # Позиция внутри сообщения парсера JSON: он пишет её по-английски и
      # только текстом, поэтому вынимаем регуляркой.
      POSITION = /line (\d+),? column (\d+)/

      # @param path [String]
      # @return [Hash] разобранный документ со строковыми ключами
      # @raise [SpecLoadError]
      def self.read(path)
        new(path).read
      end

      # @param path [String]
      def initialize(path)
        @path = path
      end

      # @return [Hash]
      def read
        text = read_text
        fail_load(Texts.t('spec_loader.reader.empty'), '$') if text.strip.empty?

        data = parse(text)
        fail_load(Texts.t('spec_loader.reader.no_document'), '$') if data.nil?
        unless data.is_a?(Hash)
          fail_load(Texts.t('spec_loader.reader.root_type', type: TypeName.of(data)), '$')
        end

        normalize(data)
      end

      private

      def read_text
        File.read(@path, mode: 'r:bom|utf-8')
      rescue Errno::ENOENT
        fail_load(Texts.t('spec_loader.reader.not_found'))
      rescue Errno::EISDIR
        fail_load(Texts.t('spec_loader.reader.directory'))
      rescue SystemCallError => e
        fail_load(Texts.t('spec_loader.reader.unreadable', reason: e.message))
      end

      def parse(text)
        json?(text) ? parse_json(text) : parse_yaml(text)
      end

      def json?(text)
        extension = File.extname(@path).downcase
        return true if JSON_EXTENSIONS.include?(extension)
        return false if YAML_EXTENSIONS.include?(extension)

        text.lstrip.start_with?('{', '[')
      end

      def parse_yaml(text)
        Psych.safe_load(text, permitted_classes: YAML_CLASSES, aliases: true, filename: @path)
      rescue Psych::SyntaxError => e
        problem = [e.problem, e.context].compact.join(' ')
        fail_load(Texts.t('spec_loader.reader.yaml_syntax', problem: problem),
                  position(e.line, e.column))
      rescue Psych::Exception => e
        fail_load(Texts.t('spec_loader.reader.yaml_error', reason: e.message))
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        detail = e.message.lines.first.to_s.strip
        found = detail.match(POSITION)
        fail_load(Texts.t('spec_loader.reader.json_syntax', problem: detail),
                  found && position(found[1], found[2]))
      end

      # Позиция ошибки синтаксиса — тоже текст для человека, поэтому её
      # формат живёт в локали, а не в интерполяции.
      def position(line, column)
        Texts.t('spec_loader.position', line: line, column: column)
      end

      # YAML отдаёт целочисленные ключи для незакавыченных кодов ответа
      # (200:), а OpenAPI ждёт строки; остальной конвейер рассчитывает
      # только на строковые ключи.
      def normalize(value)
        case value
        when Hash then value.to_h { |key, child| [key.to_s, normalize(child)] }
        when Array then value.map { |child| normalize(child) }
        else value
        end
      end

      def fail_load(message, location = nil)
        raise SpecLoadError.new(message, file: @path, path: location)
      end
    end
  end
end
