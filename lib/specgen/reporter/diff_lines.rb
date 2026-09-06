# frozen_string_literal: true

module SpecGen
  module Reporter
    # Сравнение двух версий спецификации на экране: группы по разделам IR, по
    # две строки на изменение — что было и что стало, а под ними адрес в
    # спецификации.
    #
    # Пометка влияния стоит у каждого изменения, а не только у тех, что
    # меняют сервис: читателю нужно знать не только «что перегенерировать»,
    # но и «почему вот это перегенерировать не надо». Итог называет обе
    # цифры, потому что ответ на вопрос «надо ли трогать интеграцию» — это
    # вторая из них.
    class DiffLines
      INDENT = Format::INDENT

      # Порядок задаётся здесь ещё раз, хотя Diff.call уже отсортировал:
      # группировка по разделам верна только на отсортированном списке, и
      # экран не должен зависеть от того, кто его собрал.
      # @param changes [Array<Diff::Change>]
      # @param old [String] имя прежнего файла для заголовка
      # @param new [String] имя нового файла
      def initialize(changes, old:, new:)
        @changes = changes.sort_by(&:sort_key)
        @old = old
        @new = new
      end

      # @return [Array<String>] строки вывода без завершающих переводов строк
      def lines
        return [heading, Texts.t('diff.none')] if @changes.empty?

        [heading, *groups, '', total]
      end

      # @param io [IO]
      # @return [void]
      def print_to(io)
        lines.each { |line| io.puts(line) }
      end

      private

      def heading
        Texts.t('diff.heading', old: @old, new: @new)
      end

      def groups
        @changes.group_by(&:area).flat_map do |area, changes|
          ['', Texts.t("diff.area.#{area}"), *changes.flat_map { |change| change_lines(change) }]
        end
      end

      def change_lines(change)
        line = "#{INDENT}#{Texts.t("diff.kind.#{change.kind}")}: #{values(change)}"
        [[line, Texts.t("diff.impact.#{change.impact}")].join('  '),
         "#{INDENT * 3}#{change.json_path}"]
      end

      # Появление и исчезновение показывают одно значение, всё остальное —
      # переход: иначе смена имени заголовка на «не выведено» читалась бы как
      # появление заголовка.
      def values(change)
        return render(change.after) if change.added?
        return render(change.before) if change.removed?

        "#{render(change.before)} -> #{render(change.after)}"
      end

      def render(value)
        return Diff::Change::NONE if value.nil?

        value.is_a?(Array) ? value.join(', ') : value.to_s
      end

      def total
        Texts.t('diff.total', total: @changes.size, code: @changes.count(&:code?))
      end
    end
  end
end
