# frozen_string_literal: true

module SpecGen
  module Reporter
    # Секция выведенных фактов в сводке: единицы суммы, статусы, ошибки,
    # вебхук, идемпотентность — по строке на факт, с источником и
    # уверенностью рядом, как у провайдера и авторизации выше.
    #
    # Каждый факт печатается и тогда, когда его не удалось вывести: строка
    # «не выведено» с обоснованием — тот самый пункт ручной работы, который
    # человек должен сделать, и молчать о нём экран не имеет права.
    class DerivationLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] печатать обоснование под каждым значением
      def initialize(profile, explain: false)
        @profile = profile
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        units_lines + status_lines
      end

      private

      attr_reader :profile, :explain

      def status_lines
        mappings = profile.status_map
        return [Texts.t('summary.statuses_none')] if mappings.empty?

        mapped, unmapped = mappings.partition(&:mapped?)
        width = mappings.map { |mapping| mapping.provider_status.size }.max
        [Texts.t('summary.statuses', mapped: mapped.size, unmapped: unmapped.size)] +
          mappings.flat_map { |mapping| status_line(mapping, width) }
      end

      def status_line(mapping, width)
        ["#{INDENT}#{mapping.provider_status.ljust(width)}  -> #{Format.derived(mapping.internal)}",
         *evidence(mapping.internal, depth: 2)]
      end

      def units_lines
        units = profile.units
        return [Texts.t('summary.units_none')] if units.nil?

        [units_line(units), *evidence(units.unit), *evidence(units.exponent),
         *evidence(units.currency)]
      end

      def units_line(units)
        currency = Format.derived(units.currency)
        unless units.known?
          missing = [units.unit, units.exponent].find(&:unknown?)
          return Texts.t('summary.units_unknown', evidence: missing.evidence, currency: currency)
        end

        source = units.unit.value == :minor ? units.exponent : units.unit
        Texts.t('summary.units', unit: units.unit.value, multiplier: units.multiplier,
                                 evidence: source.evidence, currency: currency)
      end

      def evidence(derived, depth: 1)
        Format.evidence(derived, explain: explain, depth: depth)
      end
    end
  end
end
