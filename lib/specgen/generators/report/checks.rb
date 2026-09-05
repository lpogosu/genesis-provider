# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Раздел 1: сверка записанных фикстур со схемами спецификации.
      #
      # Стоит рядом со списком артефактов намеренно. Это факт о прогоне и о
      # записанных файлах, а не о самой спецификации: покрытие (раздел 2)
      # отвечает, сколько спецификации задействовано, а сверка — правильно ли
      # задействованное собрано. Разделы 3, 5 и 6 разбирают предупреждения по
      # кодам, и заводить там восьмой раздел ради четырёх чисел значило бы
      # разнести один ответ по двум местам.
      class Checks < Base
        # Сколько находок одного вида показывать; остальные — числом.
        MAX_ITEMS = 8
        # Порядок разбора: сначала настоящие расхождения, потом наши
        # заглушки, потом то, что проверить нечем.
        ORDER = %i[failed synthesized unchecked].freeze

        # Один вид находок: заголовок, что он значит, строки и скрытое.
        Group = Struct.new(:kind, :title, :explanation, :items, :hidden, :more,
                           keyword_init: true)

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}] презентеры сервиса
        # @param result [Validators::Result]
        def initialize(ctx, parts, result)
          super(ctx, parts)
          @result = result
        end

        # @return [String] одна строка с числами прогона
        def line
          t('checks_line', total: @result.total, passed: @result.count(:passed),
                           failed: @result.count(:failed),
                           synthesized: @result.count(:synthesized),
                           unchecked: @result.count(:unchecked))
        end

        # @return [Boolean] есть о чём рассказать под строкой с числами
        def problems?
          @result.problems?
        end

        # @return [Array<Group>] непустые виды находок в порядке ORDER
        def groups
          ORDER.filter_map { |kind| group(kind) }
        end

        private

        def group(kind)
          found = @result.problems.select { |finding| finding.kind == kind }
          return nil if found.empty?

          hidden = [found.size - MAX_ITEMS, 0].max
          Group.new(kind: kind, title: t("checks_kind_#{kind}", count: found.size),
                    explanation: t("checks_meaning_#{kind}"),
                    items: found.first(MAX_ITEMS).map { |finding| item(finding) },
                    hidden: hidden, more: t('checks_more', count: hidden))
        end

        # Место в спецификации печатается той же нотацией JSONPath, что и
        # цели overlay: по нему открывают спецификацию и смотрят схему.
        def item(finding)
          t('checks_item', subject: finding.subject, reason: finding.message,
                           place: code(finding.json_path.to_s))
        end
      end
    end
  end
end
