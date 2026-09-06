# frozen_string_literal: true

module SpecGen
  module Validators
    # Итог стадии проверки: все находки и числа по видам.
    #
    # Тело, которого спецификация не обещала (операция без `requestBody`,
    # ответ 204), находкой не становится вовсе: проверять там нечего, и
    # ноль в знаменателе честнее единицы.
    class Result
      # @return [Array<Finding>] в порядке фикстур: запросы, ответы, уведомления
      attr_reader :findings

      # @param findings [Array<Finding>]
      def initialize(findings = [])
        @findings = findings.freeze
      end

      # @param kind [Symbol] один из Finding::KINDS
      # @return [Integer]
      def count(kind)
        findings.count { |finding| finding.kind == kind }
      end

      # @return [Integer] сколько тел вообще проверялось
      def total
        findings.size
      end

      # @return [Array<Finding>] всё, кроме прошедшего проверку
      def problems
        findings.select(&:problem?)
      end

      # @return [Boolean]
      def problems?
        findings.any?(&:problem?)
      end

      # Числа наружу: их кладёт в Artifact#metrics генератор отчёта, так же
      # как покрытие. Префикс и набор видов задаёт вызывающий, потому что
      # проверок две: сверка фикстур со схемами и прогон собранного класса, и
      # смешивать их числа в одной таблице нельзя.
      #
      # @param prefix [Symbol] приставка ключей
      # @param kinds [Array<Symbol>] виды находок, которые считаем
      # @return [Hash{Symbol => Integer}]
      def to_h(prefix: :checks, kinds: Finding::KINDS)
        kinds.to_h { |kind| [:"#{prefix}_#{kind}", count(kind)] }
             .merge("#{prefix}_total": total)
      end
    end
  end
end
