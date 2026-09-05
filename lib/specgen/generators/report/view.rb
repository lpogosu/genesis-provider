# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Представление для templates/report.md.erb: семь разделов отчёта.
      #
      # Строится на тех же презентерах, что и сервис (Service::View и его
      # части), и на тех же презентерах фикстур, поэтому отчёт говорит о том
      # коде, который записан рядом, а не о том, который мог бы получиться.
      class View
        include Markdown

        # @param profile [IR::ProviderProfile]
        # @param rules [Rules::Registry]
        # @param naming [Naming]
        # @param artifacts [Array<Artifact>] уже записанные артефакты прогона
        # @param checks [Validators::Result] сверка фикстур со схемами
        #   спецификации; её числа печатает раздел 1
        def initialize(profile:, rules:, naming:, artifacts: [], checks: Validators::Result.new)
          @service = Service::View.new(profile: profile, rules: rules, naming: naming)
          @ctx = @service.context
          @parts = @service.parts.merge(view: @service)
          @artifacts = artifacts
          @result = checks
        end

        # @return [Binding] контекст рендеринга ERB
        def template_binding
          binding
        end

        # @return [String] заголовок спецификации или slug
        def provider_title
          @service.provider_title
        end

        # @return [String]
        def provider_slug
          @ctx.naming.slug
        end

        # @return [String]
        def spec_file
          @service.spec_file
        end

        # @return [String]
        def spec_version
          @service.spec_version
        end

        # @return [String]
        def oas_version
          @service.oas_version
        end

        # @return [String] полное имя класса сервиса
        def class_name
          @ctx.full_class_name
        end

        # @return [String] имя файла сервиса
        def service_file
          @ctx.naming.file_name
        end

        # @return [Array<Array(String, String)>] раздел 1
        def summary_rows
          stats.rows
        end

        # @return [Array<Array(String, String, String)>] раздел 1, артефакты
        def artifact_rows
          stats.artifact_rows(@artifacts)
        end

        # @return [Overlay::Result, nil] раздел 1: что сделал файл --overlay;
        #   nil, если переопределений не подключали
        def overlay
          @ctx.profile.overlay
        end

        # Переопределённое человеком обязано быть видно рядом с тем, из чего
        # собран сервис: иначе читатель отчёта считает написанное свойством
        # спецификации.
        # @return [Array<Array(String, String, String)>] раздел 1, действия overlay
        def overlay_rows
          overlay.applied.map do |action|
            [code(action.target), t("overlay_kind_#{action.kind}"), action.description]
          end
        end

        # @return [Checks] раздел 1: сверка фикстур со схемами спецификации
        def checks
          @checks ||= Checks.new(@ctx, @parts, @result)
        end

        # @return [Coverage] раздел 2
        def coverage
          @coverage ||= Coverage.new(@ctx, @parts)
        end

        # @return [String] роли, которые сервис читает из входящих тел
        def read_roles
          codes(CoverageFields::READ_ROLES)
        end

        # @param dimension [Dimension]
        # @return [String] название измерения по-русски
        def dimension_name(dimension)
          Texts.t("generators.report.dim_#{dimension.key}")
        end

        # Непокрытое по абзацу на измерение: заголовок, список первых
        # элементов с причиной и число оставшихся.
        # @return [String]
        def coverage_gap_blocks
          blocks = coverage.dimensions.reject { |dimension| dimension.gaps.empty? }
          blocks.map { |dimension| gap_block(dimension).join("\n") }.join("\n\n")
        end

        # @return [Warnings] разделы 3, 5 и 6
        def warnings
          @warnings ||= Warnings.new(@ctx, @parts)
        end

        # @return [Operations] раздел 4
        def operations
          @operations ||= Operations.new(@ctx, @parts)
        end

        # @return [Array<String>] раздел 7
        def checklist
          @checklist ||= Checklist.new(@ctx, @parts).items
        end

        # @return [Integer] сколько элементов показывает группа справок
        def notes_limit
          Warnings::MAX_NOTES
        end

        # @return [String] «7 пунктов» с формой множественного числа локали
        def checklist_total
          Texts.plural(checklist.size, 'item')
        end

        # @param key [String] ключ под generators.report
        # @return [String]
        def t(key, **params)
          Texts.t("generators.report.#{key}", **params)
        end

        private

        def gap_block(dimension)
          heading = t('gaps_heading', count: dimension.uncovered)
          lines = ["**#{dimension_name(dimension)}** — #{heading}", '']
          lines += list(dimension.shown_gaps.map { |element, reason| "`#{element}` — #{reason}" })
          return lines if dimension.hidden_gaps.zero?

          lines + ["- #{t('gaps_more', count: dimension.hidden_gaps)}"]
        end

        def stats
          @stats ||= Stats.new(@ctx, @parts)
        end
      end
    end
  end
end
