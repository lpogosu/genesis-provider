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
          idempotency_header: profile.idempotency&.header&.value,
          confidence: confidence, assumptions: assumptions }
      end

      # Три уровня доверия в числах: сколько выведенных значений профиля
      # взято из структуры спецификации, из overlay, из справочников и
      # эвристикой, сколько не вывелось и сколько эвристик легло ниже порога
      # матчеров. Считается по сериализованному профилю: каждый Derived
      # превращается в хеш с ключами source, confidence и evidence, а других
      # хешей такой формы в IR нет.
      # @return [Hash{Symbol => Integer, Float}]
      def confidence
        counts = Hash.new(0)
        each_derived(profile.to_h) do |node|
          counts[node[:source]] += 1
          low = node[:source] == :heuristic && node[:confidence] < threshold
          counts[:heuristic_low] += 1 if low
        end
        IR::Roles::SOURCE.to_h { |source| [source, counts[source]] }
                         .merge(heuristic_low: counts[:heuristic_low], threshold: threshold)
      end

      def each_derived(node, &block)
        case node
        when Hash
          return yield(node) if derived_hash?(node)

          node.each_value { |value| each_derived(value, &block) }
        when Array
          node.each { |value| each_derived(value, &block) }
        end
      end

      def derived_hash?(hash)
        %i[source confidence evidence].all? { |key| hash.key?(key) } &&
          IR::Roles::SOURCE.include?(hash[:source])
      end

      def threshold
        rules.roles.scoring(:threshold)
      end

      # Те же допущения, что печатает раздел 9 INTEGRATION.md, теми же
      # презентерами: контракт, допущения проекта, выражения платформы и
      # допущения этого прогона.
      # @return [Hash{Symbol => String, Array<String>}]
      def assumptions
        section = integration.assumptions
        { contract: section.contract_line, project: section.project_lines,
          platform: section.platform_line, run: integration.run_assumptions }
      end

      def integration
        @integration ||= Generators::Integration::View.new(profile: profile, rules: rules,
                                                           naming: naming)
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
