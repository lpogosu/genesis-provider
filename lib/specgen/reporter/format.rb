# frozen_string_literal: true

module SpecGen
  module Reporter
    # Как на экране выглядят выведенное значение и его обоснование. Общий для
    # всех секций сводки, чтобы один и тот же факт никогда не печатался двумя
    # способами.
    #
    #   derived(d)   "acmepay (эвристика 0.80)" или «не выведено»
    #   evidence(d)  строка обоснования с отступом — только когда её просят
    module Format
      INDENT = '  '

      # @param derived [IR::Derived, nil]
      # @return [String] значение с источником и уверенностью
      def self.derived(derived)
        return Texts.t('summary.unknown') if derived.nil? || derived.unknown?

        "#{derived.value} (#{Texts.t("source.#{derived.source}")} " \
          "#{format('%.2f', derived.confidence)})"
      end

      # @param derived [IR::Derived, nil]
      # @param explain [Boolean] нужно ли обоснование вообще
      # @param depth [Integer] уровень отступа объясняемой строки
      # @return [Array<String>] ноль или одна строка
      def self.evidence(derived, explain:, depth: 1)
        return [] unless explain && derived&.evidence

        ["#{INDENT * (depth + 1)}= #{derived.evidence}"]
      end

      # @param value [Object] значение ограничения из спецификации
      # @return [String] компактно, без Ruby-кавычек у простых строк
      def self.constraint(value)
        case value
        when Array then value.map { |item| constraint(item) }.join(', ')
        when String then value
        else value.inspect
        end
      end
    end
  end
end
