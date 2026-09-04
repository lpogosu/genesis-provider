# frozen_string_literal: true

module SpecGen
  module Reporter
    # Секция условий взаимодействия в сводке: по строке на условие — вид,
    # субъект (операция или поле) и значение с источником и уверенностью.
    # Условие, прочитанное из прозы, отличается от прочитанного из ключевых
    # слов ровно этим хвостом: «эвристика 0.60» против «задано явно 1.00».
    class ConditionLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] печатать обоснование под каждым условием
      def initialize(profile, explain: false)
        @conditions = profile.conditions
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return [Texts.t('summary.conditions_none')] if @conditions.empty?

        [Texts.t('summary.conditions', count: @conditions.size)] +
          @conditions.flat_map { |condition| condition_lines(condition) }
      end

      private

      def condition_lines(condition)
        columns = [INDENT + condition.kind.to_s.ljust(kind_width),
                   subject(condition).ljust(subject_width), value_text(condition)]
        [columns.join('  '), *Format.evidence(condition.value, explain: @explain, depth: 2)]
      end

      def subject(condition)
        condition.field || condition.operation.to_s
      end

      def value_text(condition)
        derived = condition.value
        "#{Format.constraint(derived.value)} (#{Texts.t("source.#{derived.source}")} " \
          "#{format('%.2f', derived.confidence)})"
      end

      def kind_width
        @kind_width ||= @conditions.map { |condition| condition.kind.to_s.size }.max
      end

      def subject_width
        @subject_width ||= @conditions.map { |condition| subject(condition).size }.max
      end
    end
  end
end
