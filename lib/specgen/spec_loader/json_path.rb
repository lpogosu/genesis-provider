# frozen_string_literal: true

require 'strscan'

module SpecGen
  module SpecLoader
    # Собирает строки JSONPath из массивов ключей в той скобочной нотации,
    # которую спецификация OpenAPI Overlay применяет к ключам со
    # специальными символами, и разбирает их обратно:
    #
    #   JsonPath.build(['paths', '/payouts', 'post']) # => "$.paths['/payouts'].post"
    #   JsonPath.build(['servers', 0, 'url'])         # => "$.servers[0].url"
    #   JsonPath.parse("$.paths['/payouts'].post")    # => ['paths', '/payouts', 'post']
    #
    # Разбор — строгая обратная операция к сборке, и это граница
    # поддерживаемого подмножества JSONPath: цели действий overlay мы сами же
    # и печатаем в предупреждениях и в report.md, поэтому разбирать умеем
    # ровно то, что печатаем. Рекурсивный спуск `..`, звёздочка, срез и
    # фильтр `[?(...)]` не поддерживаются намеренно — движок JSONPath общего
    # вида решал бы задачу, которой у нас нет, а цель, адресующая несколько
    # узлов сразу, делает «переопределено вот это» непроверяемым.
    module JsonPath
      ROOT = '$'
      IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      # Один сегмент пути: имя через точку, индекс массива, ключ в скобках в
      # одинарных или двойных кавычках (RFC 9535 разрешает обе формы,
      # #build печатает одинарные).
      SEGMENT = /
        \.(?<name>[A-Za-z_][A-Za-z0-9_]*)
        |\[(?<index>\d+)\]
        |\['(?<single>(?:[^'\\]|\\.)*)'\]
        |\["(?<double>(?:[^"\\]|\\.)*)"\]
      /x

      # @param keys [Array<String, Integer>] путь ключей от корня документа
      # @return [String]
      def self.build(keys)
        keys.reduce(ROOT) { |path, key| path + segment(key) }
      end

      # @param key [String, Integer]
      # @return [String] один сегмент пути
      def self.segment(key)
        return "[#{key}]" if key.is_a?(Integer)

        key = key.to_s
        return ".#{key}" if key.match?(IDENTIFIER)

        "['#{key.gsub(/['\\]/) { |char| "\\#{char}" }}']"
      end

      # @param expression [String] выражение JSONPath
      # @return [Array<String, Integer>, nil] путь ключей от корня либо nil,
      #   если выражение написано синтаксисом вне подмножества
      def self.parse(expression)
        text = expression.to_s.strip
        return nil unless text.start_with?(ROOT)

        scanner = StringScanner.new(text[ROOT.length..])
        keys = []
        until scanner.eos?
          return nil unless scanner.scan(SEGMENT)

          keys << key_of(scanner)
        end
        keys
      end

      # @param scanner [StringScanner] сразу после успешного SEGMENT
      # @return [String, Integer] ключ этого сегмента
      def self.key_of(scanner)
        return scanner[:name] if scanner[:name]
        return Integer(scanner[:index], 10) if scanner[:index]

        unescape(scanner[:single] || scanner[:double])
      end

      # @param text [String] содержимое кавычек как оно записано
      # @return [String] с раскрытыми экранированными символами
      def self.unescape(text)
        text.gsub(/\\(.)/) { Regexp.last_match(1) }
      end
    end
  end
end
