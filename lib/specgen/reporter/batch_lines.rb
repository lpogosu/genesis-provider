# frozen_string_literal: true

module SpecGen
  module Reporter
    # Сводка пакетного прогона строками: заголовок, выровненная таблица по
    # строке на спецификацию, итог и — отдельным блоком — тексты ошибок.
    #
    # Живёт здесь, а не в CLI, по той же причине, что и Summary: CLI
    # разбирает аргументы и печатает готовые строки, а как выглядит вывод,
    # решает Reporter. Ошибки вынесены под таблицу намеренно: сообщение
    # загрузчика длиной в строку экрана ломает выравнивание колонок, а
    # выравнивание — единственное, ради чего таблица вообще нужна.
    class BatchLines
      # Прочерк в ячейке: числа у неразобранной спецификации нет, а пустая
      # ячейка читается как ноль. Колонок восемь, и заголовки у них
      # короткие намеренно: строка таблицы обязана уместиться в терминал
      # шириной 120 знаков вместе с самым длинным путём спецификации.
      EMPTY = '—'
      COLUMNS = %w[spec provider operations roles coverage contract warnings artifacts].freeze
      GAP = '  '

      # @param rows [Array<Batch::Row>]
      # @param dir [String] каталог, по которому шёл прогон
      def initialize(rows, dir:)
        @rows = rows
        @dir = dir
      end

      # @return [Array<String>] строки вывода без завершающих переводов строк
      def lines
        [Texts.t('cli.batch_heading', dir: @dir), *table, total, *errors]
      end

      # @param io [IO]
      # @return [void]
      def print_to(io)
        lines.each { |line| io.puts(line) }
      end

      private

      def table
        rows = [header] + @rows.map { |row| cells(row) }
        widths = rows.transpose.map { |column| column.map(&:length).max }
        rows.map { |row| row.zip(widths).map { |cell, width| cell.ljust(width) }.join(GAP).rstrip }
      end

      def header
        COLUMNS.map { |key| Texts.t("cli.batch_column.#{key}") }
      end

      def cells(row)
        return [row.file, Texts.t('cli.batch_failed'), *Array.new(6, EMPTY)] unless row.ok?

        [row.file, row.provider, row.operations.to_s, "#{row.roles}/#{row.operations}",
         "#{row.coverage} %", "#{row.contract} %", row.warnings.to_s, row.artifacts.to_s]
      end

      def total
        Texts.t('cli.batch_total', specs: Texts.plural(@rows.size, 'spec'),
                                   ok: @rows.count(&:ok?), total: @rows.size)
      end

      def errors
        failed = @rows.reject(&:ok?)
        return [] if failed.empty?

        ['', Texts.t('cli.batch_errors')] + failed.map { |row| "  #{row.file}: #{row.error}" }
      end
    end
  end
end
