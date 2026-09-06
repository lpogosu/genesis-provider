# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Одно измерение покрытия спецификации сгенерированной интеграцией.
      #
      #   key           ключ названия измерения в locales/*/generators.yml
      #   total         сколько элементов спецификации этого вида найдено
      #   covered       сколько из них задействовано в сгенерированном коде
      #   gaps          [Gap] — непокрытое поимённо, с причиной и корзиной;
      #                 непокрытое без причины было бы обвинением, а не отчётом
      #   out_of_scope  сколько из непокрытого контракт не может использовать
      #                 по построению: знаменатель второй цифры покрытия
      Dimension = Struct.new(:key, :total, :covered, :gaps, :out_of_scope, keyword_init: true)

      # Проценты и выборки Dimension.
      class Dimension
        # Пропуски измерения из одной корзины. Раздел о покрытии печатает
        # корзинами, а не измерениями: перечислять поимённо стоит только то,
        # что адресовано человеку, а измерение остаётся вторым уровнем
        # группировки внутри корзины.
        # @param bucket [Symbol] :out_of_contract, :structural либо :manual
        # @return [Array<Gap>]
        def gaps_in(bucket)
          gaps.select { |gap| gap.bucket == bucket }
        end

        # @return [Integer, nil] доля покрытых элементов; nil у измерения,
        #   в котором нечего покрывать
        def percent
          return nil if empty?

          ((covered.to_f / total) * 100).round
        end

        # @return [Boolean] спецификация не дала ни одного элемента этого вида
        def empty?
          total.to_i.zero?
        end

        # Измерение без элементов не печатает 100 %: покрывать в нём нечего,
        # и круглая цифра выглядела бы достижением там, где нет данных. На
        # итоговую цифру покрытия это не влияет — она считается суммой
        # покрытого к сумме найденного, а пустое измерение не добавляет ни
        # к числителю, ни к знаменателю.
        # @return [String] "76 %" либо «нечего покрывать»
        def percent_text
          return Texts.t('generators.report.coverage_empty') if empty?

          "#{percent} %"
        end

        # @return [Integer]
        def uncovered
          total.to_i - covered.to_i
        end

        # Знаменатель второй цифры покрытия: найденное минус то, чему в
        # методах контракта нет места по построению. Исключается только
        # непокрытое, поэтому число никогда не меньше покрытого.
        # @return [Integer]
        def in_scope_total
          total.to_i - out_of_scope.to_i
        end

        # @return [Integer] сколько элементов измерения вне границ контракта
        def excluded
          out_of_scope.to_i
        end
      end
    end
  end
end
