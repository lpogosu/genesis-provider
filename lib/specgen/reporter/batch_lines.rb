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
        [Texts.t('cli.batch_heading', dir: @dir), *table, total, *median_line, *errors]
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

      # Медиана колонки «В контракте» одной строкой. Читатель сводки видит
      # разброс первой колонки (23 % у Adyen Payout, 75 % у NovaPay) и делает
      # из него вывод об инструменте, хотя разброс описывает спецификации:
      # чем больше в файле посторонних ресурсов, тем ниже первая цифра.
      # Медиана второй колонки отвечает на этот вопрос до того, как он задан.
      # Медиана, а не среднее: одна спецификация с сотней чужих операций не
      # должна двигать итог прогона.
      def median_line
        values = @rows.select(&:ok?).filter_map(&:contract).sort
        return [] if values.empty?

        middle = values.size / 2
        value = values.size.odd? ? values[middle] : ((values[middle - 1] + values[middle]) / 2.0)
        [Texts.t('cli.batch_median', value: format('%g', value.round(1)))]
      end

      def errors
        failed = @rows.reject(&:ok?)
        return [] if failed.empty?

        ['', Texts.t('cli.batch_errors')] + failed.map { |row| "  #{row.file}: #{row.error}" }
      end
    end
  end
end
