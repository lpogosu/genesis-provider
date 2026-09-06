# frozen_string_literal: true

module SpecGen
  module Web
    # Сводка разбора для экрана: числа из IR, готовые строки от презентеров
    # CLI и покрытие от того же класса, который печатает его в report.md.
    #
    # Ничего не считается здесь заново. Покрытие — Report::Coverage, строка
    # об авторизации и о единицах — презентеры Reporter, базовый URL —
    # Service::Context, тот самый, из которого шаблон печатает константу
    # BASE_URL. Разойтись экрану и терминалу не на чем.
    class Summary
      # @param profile [IR::ProviderProfile]
      # @param rules [Rules::Registry]
      # @param document [SpecLoader::Document]
      # @param naming [Generators::Naming]
      def initialize(profile:, rules:, document:, naming:)
        @profile = profile
        @rules = rules
        @document = document
        @naming = naming
      end

      # @return [Hash] тело поля `summary` в ответе API
      def to_h
        counts.merge(texts).merge(facts)
      end

      private

      attr_reader :profile, :rules, :document, :naming

      def counts
        { operations: profile.operations.size,
          operations_with_role: profile.operations.count { |op| !op.unmapped? },
          schemas: profile.schemas.size, fields: fields_count,
          coverage_percent: coverage.percent,
          contract_coverage_percent: coverage.in_scope_percent, warnings: warnings }
      end

      def texts
        { auth: AuthText.new(profile, document).text,
          units: UnitsText.new(profile).text,
          base_url: service.context.sandbox_url }
      end

      def facts
        { statuses: statuses, events: events, webhook: webhook,
          idempotency_header: profile.idempotency&.header&.value }
      end

      # Столько же полей, сколько считает шапка экрана `analyze`.
      def fields_count
        profile.schemas.each_value.sum { |schema| schema.fields.size }
      end

      def warnings
        grouped = profile.warnings_by_severity
        { total: profile.warnings.size }
          .merge(grouped.transform_values(&:size))
      end

      def statuses
        { total: profile.status_map.size, mapped: profile.status_map.count(&:mapped?) }
      end

      def events
        all = profile.webhooks.flat_map(&:events)
        { total: all.size, mapped: all.count(&:mapped?) }
      end

      def webhook
        webhook = profile.webhooks.first
        signature = webhook&.signature
        { present: !webhook.nil?, path: webhook&.path,
          signature_header: signature&.header&.value }
      end

      def coverage
        @coverage ||= Generators::Report::View.new(profile: profile, rules: rules,
                                                   naming: naming).coverage
      end

      def service
        @service ||= Generators::Service::View.new(profile: profile, rules: rules, naming: naming)
      end
    end
  end
end
