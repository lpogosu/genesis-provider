# frozen_string_literal: true

module SpecGen
  module Generators
    # Разметка Markdown для документов, которые пишет генератор
    # (INTEGRATION.md, report.md): таблицы, код, ячейки. Всё, что презентеры
    # кладут в документ, проходит здесь, чтобы вертикальная черта в значении
    # не ломала таблицу, а пустая ячейка не выглядела пропуском.
    module Markdown
      EMPTY = '—'
      # Ширина абзаца документа. Тексты локали приходят со своими переносами,
      # но подстановки (список ролей, имя базового класса) их сбивают, и
      # абзац переносится заново — на одной ширине для всего документа.
      WIDTH = 78

      module_function

      # @param text [String]
      # @param width [Integer]
      # @return [String] абзац, перенесённый по словам
      def paragraph(text, width: WIDTH)
        Ruby.wrap(text.gsub(/\s+/, ' ').strip, width).join("\n")
      end

      # @param headers [Array<String>]
      # @param rows [Array<Array<Object>>]
      # @return [Array<String>] строки таблицы с разделителем заголовка
      def table(headers, rows)
        [row(headers), "|#{headers.map { '---' }.join('|')}|"] + rows.map { |cells| row(cells) }
      end

      # @param cells [Array<Object>]
      # @return [String] "| a | b |"
      def row(cells)
        "| #{cells.map { |cell| cell(cell) }.join(' | ')} |"
      end

      # @param value [Object]
      # @return [String] текст ячейки в одну строку; пусто — EMPTY
      def cell(value)
        text = value.to_s.gsub(/\s*\n\s*/, ' ').gsub('|', '\\|').strip
        text.empty? ? EMPTY : text
      end

      # @param value [Object]
      # @return [String] "`value`"
      def code(value)
        "`#{value}`"
      end

      # @param items [Array<Object>]
      # @return [String] "`a`, `b`" — или EMPTY для пустого списка
      def codes(items)
        items.empty? ? EMPTY : items.map { |item| code(item) }.join(', ')
      end

      # @param items [Array<String>]
      # @return [Array<String>] маркированный список
      def list(items)
        items.map { |item| "- #{item}" }
      end

      # @param items [Array<String>]
      # @return [Array<String>] нумерованный список
      def numbered(items)
        items.each_with_index.map { |item, index| "#{index + 1}. #{item}" }
      end

      # @param lines [Array<String>]
      # @param language [String]
      # @return [Array<String>] блок кода
      def fence(lines, language)
        ["```#{language}", *lines, '```']
      end
    end
  end
end
