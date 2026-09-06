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
        # @param run [Validators::Result] прогон собранного класса на его же
        #   фикстурах; его числа печатает тот же раздел 1
        def initialize(profile:, rules:, naming:, artifacts: [], checks: Validators::Result.new,
                       run: Validators::Result.new)
          @service = Service::View.new(profile: profile, rules: rules, naming: naming)
          @ctx = @service.context
          @parts = @service.parts.merge(view: @service)
          @artifacts = artifacts
          @result = checks
          @run_result = run
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

        # @return [Run] раздел 1: прогон собранного класса на его фикстурах
        def run
          @run ||= Run.new(@ctx, @parts, @run_result)
        end

        # @return [String] базовый класс платформы, который подменяет прогон
        def base_class
          @ctx.contract.base_class
        end

        # @return [Coverage] раздел 2
        def coverage
          @coverage ||= Coverage.new(@ctx, @parts)
        end

        # @return [String] роли, которые сервис читает из входящих тел
        def read_roles
          codes(CoverageFields::READ_ROLES)
        end

        # Абзац о том, почему цифр в разделе две и чем они отличаются.
        # @return [String] раздел 2
        def coverage_scope_note
          paragraph(t('coverage_scope_note', base: code(@ctx.contract.base_class),
                                             roles: read_roles))
        end

        # @return [String] раздел 2: сколько элементов вычтено из знаменателя
        def coverage_scope_intro
          paragraph(t('coverage_scope_intro',
                      count: Texts.plural(coverage.out_of_scope, 'element')))
        end

        # Вычтенное поимённо по видам: без явного списка вторая цифра
        # читалась бы как подкрутка.
        # @return [String] раздел 2
        def coverage_scope_list
          rows = coverage.excluded_dimensions.map do |dimension|
            reason = t("scope_#{dimension.key}")
            "**#{dimension_name(dimension)}** — #{dimension.excluded}: #{reason}"
          end
          list(rows).join("\n")
        end

        # @return [String] раздел 2: что в знаменателе осталось и где сверить
        def coverage_scope_rest
          paragraph(t('coverage_scope_rest'))
        end

        # Сводная строка о непокрытом: сколько его и как оно делится на три
        # корзины. Без неё читатель принимает всё непокрытое за провал
        # разбора, хотя работы человека в нём — восьмая часть.
        # @return [String] раздел 2
        def coverage_buckets_line
          counts = coverage.buckets.counts
          parts = counts.map { |bucket, count| t("bucket_count_#{bucket}", count: count) }
          paragraph(t('coverage_buckets', total: coverage.buckets.total, parts: parts.join(', ')))
        end

        # @param dimension [Dimension]
        # @return [String] название измерения по-русски
        def dimension_name(dimension)
          Texts.t("generators.report.dim_#{dimension.key}")
        end

        # Корзина, адресованная человеку: перечисляется поимённо и целиком,
        # по абзацу на измерение. Полностью — потому что это и есть ответ на
        # вопрос «что мне доделать руками», и оборванный на пятнадцатом
        # элементе список этого ответа не даёт.
        # @return [String] раздел 2
        def coverage_manual_blocks
          found = coverage.buckets.of(Gap::MAIN)
          return paragraph(t('bucket_manual_none')) if found.empty?

          blocks = found.map { |dimension, gaps| manual_block(dimension, gaps).join("\n") }
          [bucket_title(Gap::MAIN), *blocks].join("\n\n")
        end

        # Корзины, в которых человеку делать нечего: число и примеры. Каждый
        # их элемент назван причиной, а причину раскладывает по корзинам
        # таблица Gap::BUCKETS, поэтому свёртка ничего не прячет.
        # @return [String] раздел 2
        def coverage_folded_blocks
          Gap::FOLDED.reject { |bucket| coverage.buckets.of(bucket).empty? }
                     .map { |bucket| folded_block(bucket) }.join("\n\n")
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

        # Заголовок корзины с её числом и объяснением, что она значит.
        def bucket_title(bucket)
          count = coverage.buckets.counts[bucket]
          paragraph("**#{t("bucket_title_#{bucket}")} — #{count}.** #{t("bucket_note_#{bucket}")}")
        end

        def manual_block(dimension, gaps)
          heading = t('gaps_heading', count: gaps.size)
          ["**#{dimension_name(dimension)}** — #{heading}", '',
           *list(gaps.map { |gap| "`#{gap.element}` — #{gap.reason}" })]
        end

        def folded_block(bucket)
          rows = coverage.buckets.of(bucket).map do |dimension, gaps|
            key = gaps.size > Gap::EXAMPLES ? 'bucket_dimension_folded' : 'bucket_dimension_all'
            t(key, dimension: dimension_name(dimension), count: gaps.size,
                   items: codes(gaps.take(Gap::EXAMPLES).map(&:element)))
          end
          [bucket_title(bucket), list(rows).join("\n")].join("\n\n")
        end

        def stats
          @stats ||= Stats.new(@ctx, @parts)
        end
      end
    end
  end
end
