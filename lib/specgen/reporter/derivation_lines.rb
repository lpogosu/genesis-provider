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
        units_lines + status_lines + webhook_lines + idempotency_lines
      end

      private

      attr_reader :profile, :explain

      def idempotency_lines
        idempotency = profile.idempotency
        return [Texts.t('summary.idempotency_none')] if idempotency.nil?

        [idempotency_line(idempotency),
         *evidence(idempotency.header), *evidence(idempotency.strategy),
         *evidence(idempotency.conflict_status)]
      end

      def idempotency_line(idempotency)
        need = Texts.t(idempotency.required ? 'summary.param_required' : 'summary.param_optional')
        Texts.t('summary.idempotency', header: idempotency.header.value, need: need,
                                       strategy: idempotency.strategy.value,
                                       dedup: dedup_text(idempotency))
      end

      def dedup_text(idempotency)
        return Texts.t('summary.idempotency_dedup_unknown') unless idempotency.dedup?

        Texts.t('summary.idempotency_dedup', status: idempotency.conflict_status.value)
      end

      def webhook_lines
        return [Texts.t('summary.webhook_none')] if profile.webhooks.empty?

        profile.webhooks.flat_map do |webhook|
          [Texts.t('summary.webhook', path: webhook.path,
                                      events: Texts.plural(webhook.events.size, 'event'),
                                      signature: signature_text(webhook.signature)),
           *signature_evidence(webhook.signature), *event_lines(webhook.events)]
        end
      end

      def signature_text(signature)
        return Texts.t('summary.webhook_unsigned') if signature.nil?

        members = %i[profile algorithm encoding payload].to_h do |member|
          derived = signature[member]
          [member, derived.known? ? derived.value : Texts.t('summary.unknown')]
        end
        Texts.t('summary.webhook_signature', header: signature.header.value, **members)
      end

      def signature_evidence(signature)
        return [] if signature.nil?

        %i[header profile algorithm encoding payload].flat_map do |member|
          evidence(signature[member])
        end
      end

      def event_lines(events)
        width = events.map { |event| event.name.size }.max || 0
        events.flat_map do |event|
          ["#{INDENT}#{event.name.ljust(width)}  -> #{Format.derived(event.internal_status)}",
           *evidence(event.internal_status, depth: 2)]
        end
      end

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
