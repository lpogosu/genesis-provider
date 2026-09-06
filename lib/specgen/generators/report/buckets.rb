# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Непокрытое, разложенное по трём корзинам Gap::BUCKETS.
      #
      # Раздел о покрытии печатается корзинами, а не измерениями: измерение
      # отвечает на вопрос «чего именно не хватило», а корзина — на вопрос
      # «моя ли это работа», и второй вопрос человек задаёт первым. Внутри
      # корзины измерение остаётся вторым уровнем группировки.
      class Buckets
        # @param dimensions [Array<Dimension>]
        def initialize(dimensions)
          @dimensions = dimensions
        end

        # @return [Hash{Symbol => Integer}] сколько непокрытого в корзине,
        #   в порядке Gap::ORDER
        def counts
          @counts ||= Gap::ORDER.to_h { |bucket| [bucket, size(bucket)] }
        end

        # @param bucket [Symbol]
        # @return [Integer]
        def size(bucket)
          of(bucket).sum { |_dimension, found| found.size }
        end

        # @return [Integer] непокрытого всего
        def total
          counts.values.sum
        end

        # @param bucket [Symbol]
        # @return [Array<Array(Dimension, Array<Gap>)>] измерения, в которых
        #   корзина непуста, в порядке измерений отчёта
        def of(bucket)
          @of ||= {}
          @of[bucket] ||= @dimensions.map { |dimension| [dimension, dimension.gaps_in(bucket)] }
                                     .reject { |_dimension, found| found.empty? }
        end
      end
    end
  end
end
