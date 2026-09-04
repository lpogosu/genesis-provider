# frozen_string_literal: true

module SpecGen
  module Matchers
    # Расстояние Левенштейна и сходство двух строк на его основе.
    #
    # Последний шаг NameMatcher: ловит опечатки и вариации написания, которых
    # нет в словаре (`amout`, `curency`). Строковая метрика не связывает
    # семантически разные имена — `sum` и `amount` далеки друг от друга при
    # любом расстоянии, — поэтому она никогда не заменяет словарь синонимов,
    # а только дополняет его, и её балл ограничен так, чтобы одна она порога
    # не достигала.
    module Levenshtein
      # Имена полей короткие; длиннее сравнивать бессмысленно и дорого.
      MAX_LENGTH = 64

      # @param left [String]
      # @param right [String]
      # @return [Integer] число вставок, удалений и замен
      def self.distance(left, right)
        a = left.to_s[0, MAX_LENGTH]
        b = right.to_s[0, MAX_LENGTH]
        return b.size if a.empty?
        return a.size if b.empty?

        previous = (0..b.size).to_a
        a.each_char.with_index(1) { |char, i| previous = row(previous, char, i, b) }
        previous.last
      end

      # Следующая строка матрицы расстояний.
      # @return [Array<Integer>]
      def self.row(previous, char, index, other)
        current = [index]
        other.each_char.with_index(1) do |candidate, j|
          cost = char == candidate ? 0 : 1
          current << [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost].min
        end
        current
      end

      # @param left [String]
      # @param right [String]
      # @return [Float] 1.0 для одинаковых строк, 0.0 для совсем разных
      def self.similarity(left, right)
        longest = [left.to_s.size, right.to_s.size].max
        return 1.0 if longest.zero?

        1.0 - (distance(left, right).to_f / longest)
      end
    end
  end
end
