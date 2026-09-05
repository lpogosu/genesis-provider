# frozen_string_literal: true

module SpecGen
  module Generators
    # Литералы и разметка Ruby для сгенерированного кода: строки, символы,
    # регулярные выражения, записи хеша, комментарии по ширине, guard-строки.
    #
    # Всё, что печатается в service.rb, проходит здесь, чтобы сгенерированный
    # файл проходил RuboCop без ручных правок: одинарные кавычки, где можно;
    # `%r{}` там, где в шаблоне есть `/`; перенос guard-строки, когда она не
    # влезает в ширину; ни одной строки длиннее WIDTH.
    module Ruby
      WIDTH = 100
      IDENT = /\A[a-z_][a-z0-9_]*[?!]?\z/i
      # Элементы, которые можно писать через %w[]: без пробелов и скобок.
      WORD = /\A[^\s\[\]'"\\]+\z/
      # С какого числа знаков целая часть разделяется подчёркиваниями: столько
      # же требует Style/NumericLiterals (MinDigits 5), то есть от 10000.
      GROUPED_DIGITS = 5
      # Цифры целой части, считая от конца, группами по три.
      GROUPS = /(\d)(?=(\d{3})+\z)/

      module_function

      # @param value [Object]
      # @return [String] строковый литерал; одинарные кавычки, если внутри
      #   нет апострофа, иначе двойные с экранированием
      def str(value)
        text = value.to_s
        return text.inspect if text.include?("'")

        "'#{text.gsub('\\') { '\\\\' }}'"
      end

      # @param value [Object]
      # @return [String] ":name" или ":\"strange name\""
      def sym(value)
        text = value.to_s
        text.match?(IDENT) ? ":#{text}" : ":#{text.inspect}"
      end

      # @param source [String] шаблон как написан в спецификации
      # @return [String] литерал регулярного выражения
      def regexp(source)
        return "/#{source}/" unless source.include?('/')
        return "%r{#{source}}" unless source.match?(/[{}]/)

        "Regexp.new(#{str(source)})"
      end

      # @param value [Object] Integer, Float, String, Symbol, nil, true,
      #   false, Array или Hash
      # @return [String] литерал Ruby
      def literal(value)
        case value
        when nil then 'nil'
        when Symbol then sym(value)
        when String then str(value)
        when Array then array(value)
        when Hash then "{ #{value.map { |k, v| "#{key(k)} #{literal(v)}" }.join(', ')} }"
        when Numeric then number(value)
        else value.to_s
        end
      end

      # Числовой литерал с разделителями-подчёркиваниями по три разряда от
      # конца целой части: `maximum: 5000000` из спецификации печатается
      # `5_000_000`, как того требует Style/NumericLiterals. Границу сумм,
      # длины и паузы печатает только этот метод — числа в сгенерированный
      # Ruby больше ниоткуда не попадают.
      # @param value [Numeric]
      # @return [String] литерал Ruby
      def number(value)
        text = value.is_a?(Rational) ? value.to_f.to_s : value.to_s
        sign = text.start_with?('-') ? '-' : ''
        whole, _, rest = text.delete_prefix('-').partition('.')
        return "#{sign}#{text.delete_prefix('-')}" unless whole.match?(/\A\d+\z/)

        whole = whole.gsub(GROUPS, '\1_') if whole.size >= GROUPED_DIGITS
        rest.empty? ? "#{sign}#{whole}" : "#{sign}#{whole}.#{rest}"
      end

      # @param items [Array]
      # @return [String] "%w[a b]" для простых строк, иначе "[1, 'x']"
      def array(items)
        return '[]' if items.empty?
        return "%w[#{items.join(' ')}]" if items.all? { |item| word?(item) }
        return "%i[#{items.join(' ')}]" if items.all? { |item| word?(item, Symbol) }

        "[#{items.map { |item| literal(item) }.join(', ')}]"
      end

      # @return [Boolean] элемент годится для %w[] / %i[]
      def word?(item, type = String)
        item.is_a?(type) && item.to_s.match?(WORD)
      end

      # @param name [Object] ключ хеша
      # @return [String] "name:" для идентификаторов, иначе "'name' =>"
      def key(name)
        text = name.to_s
        return "#{text}:" if text.match?(/\A[a-z_][a-z0-9_]*\z/)

        "#{literal(name.is_a?(Symbol) ? name : text)} =>"
      end

      # @param name [String] имя из спецификации: operationId, путь
      # @return [String] snake_case-идентификатор Ruby
      def snake(name)
        text = name.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[^A-Za-z0-9]+/, '_')
        text = text.downcase.squeeze('_').gsub(/\A_+|_+\z/, '')
        text.match?(/\A\d/) ? "op_#{text}" : text
      end

      # Переносит текст по словам в строки комментария заданной ширины.
      # @param text [String]
      # @param width [Integer] доступная ширина с учётом отступа
      # @param prefix [String] начало каждой строки
      # @return [Array<String>]
      def comment(text, width:, prefix: '# ')
        text.to_s.split("\n").flat_map do |paragraph|
          next [prefix.rstrip] if paragraph.strip.empty?

          wrap(paragraph, width - prefix.size).map { |line| "#{prefix}#{line}" }
        end
      end

      # Литерал %w[]/%i[] по строкам: продолжения выровнены по первому
      # элементу, как того требует Layout/ArrayAlignment.
      # @param items [Array<String, Symbol>]
      # @param width [Integer] доступная ширина первой строки
      # @return [Array<String>]
      def words(items, width:)
        open = items.first.is_a?(Symbol) ? '%i[' : '%w['
        lines = wrap(items.join(' '), width - open.size - 1)
        lines[-1] = "#{lines[-1]}]"
        lines.each_with_index.map { |line, index| (index.zero? ? open : ' ' * open.size) + line }
      end

      # @param text [String]
      # @param width [Integer]
      # @return [Array<String>]
      def wrap(text, width)
        text.split(/\s+/).each_with_object(['']) do |word, lines|
          if lines.last.empty? then lines[-1] = word
          elsif lines.last.size + 1 + word.size <= width then lines[-1] = "#{lines.last} #{word}"
          else lines << word
          end
        end
      end

      # Guard-строка: `return X if cond` в одну строку, если влезает, иначе
      # блок if/end с пустой строкой после — ровно так, как этого требуют
      # IfUnlessModifier, GuardClause и EmptyLineAfterGuardClause с учётом
      # LineLength.
      # @param action [String] выражение после return
      # @param condition [String]
      # @param indent [Integer] отступ, на котором строка окажется
      # @param negate [Boolean] unless вместо if
      # @return [Array<String>]
      def guard(action, condition, indent:, negate: false)
        word = negate ? 'unless' : 'if'
        line = "return #{action} #{word} #{condition}"
        return [line] if indent + line.size <= WIDTH

        ["#{word} #{condition}", "  return #{action}", 'end', '']
      end

      # Присваивание хеша-литерала: пустой хеш пишется в одну строку, иначе
      # блок с отступом. Схема без единого поля (у Adyen Transfers это
      # ApproveTransfersRequest) иначе дала бы открывающую и закрывающую
      # скобку на разных строках, а это Layout/SpaceInsideHashLiteralBraces.
      # @param name [String] имя переменной
      # @param lines [Array<String>] записи хеша
      # @return [Array<String>]
      def assign_hash(name, lines)
        return ["#{name} = {}"] if lines.empty?

        ["#{name} = {", *indent(lines, 2), '}']
      end

      # @param lines [Array<String>]
      # @param depth [Integer] число пробелов
      # @return [Array<String>] строки с отступом; пустые остаются пустыми,
      #   `rescue` и `ensure` встают на уровень `def`
      def indent(lines, depth)
        pad = ' ' * depth
        outer = ' ' * [depth - 2, 0].max
        lines.map do |line|
          next line if line.empty?

          "#{line.match?(/\A(rescue|ensure)\b/) ? outer : pad}#{line}"
        end
      end

      # Склеивает куски тела метода: сжимает повторные пустые строки и
      # убирает пустую строку в конце.
      # @param lines [Array<String>]
      # @return [Array<String>]
      def tidy(lines)
        result = lines.each_with_object([]) do |line, acc|
          acc << line unless line.empty? && (acc.empty? || acc.last.empty?)
        end
        result.pop while result.last&.empty?
        result
      end
    end
  end
end
