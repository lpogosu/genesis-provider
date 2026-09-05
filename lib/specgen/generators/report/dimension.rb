# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Одно измерение покрытия спецификации сгенерированной интеграцией.
      #
      #   key      ключ названия измерения в locales/*/generators.yml
      #   total    сколько элементов спецификации этого вида найдено
      #   covered  сколько из них задействовано в сгенерированном коде
      #   gaps     [[элемент, причина]] — непокрытое поимённо, с причиной;
      #            непокрытое без причины было бы обвинением, а не отчётом
      Dimension = Struct.new(:key, :total, :covered, :gaps, keyword_init: true)

      # Проценты и выборки Dimension.
      class Dimension
        # Сколько непокрытых элементов измерения перечислять поимённо: у
        # Adyen Transfers их под четыреста, и без ограничения раздел о
        # покрытии съедает отчёт целиком.
        MAX_GAPS = 15

        # @return [Array<Array(String, String)>] первые MAX_GAPS пропусков
        def shown_gaps
          gaps.take(MAX_GAPS)
        end

        # @return [Integer] сколько пропусков осталось за списком
        def hidden_gaps
          [gaps.size - MAX_GAPS, 0].max
        end

        # @return [Integer] доля покрытых элементов, 100 для пустого измерения
        def percent
          return 100 if total.to_i.zero?

          ((covered.to_f / total) * 100).round
        end

        # @return [Integer]
        def uncovered
          total.to_i - covered.to_i
        end
      end
    end
  end
end
