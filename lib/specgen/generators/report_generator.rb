# frozen_string_literal: true

module SpecGen
  module Generators
    # Артефакт №4: report.md — отчёт о неоднозначностях, противоречиях и
    # покрытии спецификации из templates/report.md.erb.
    #
    # Пишется всегда, даже когда предупреждений нет: «ничего не найдено» —
    # это тоже результат разбора, и его отсутствие читалось бы как пропуск
    # стадии. Генератор идёт в Runner::ORDER последним и получает список уже
    # записанных артефактов: отчёт перечисляет их с числом строк.
    #
    # Проверка результата:
    #   grep '^## ' output/report.md
    class ReportGenerator < Base
      TEMPLATE = 'report.md.erb'
      KIND = :report
      FILE_NAME = 'report.md'

      private

      def file_name
        FILE_NAME
      end

      def view
        Report::View.new(profile: profile, rules: rules, naming: naming, artifacts: artifacts,
                         checks: checks || Validators::Result.new)
      end

      # Покрытие уже посчитано для раздела 2 отчёта, сверка со спецификацией
      # — для раздела 1; пакетный прогон и тесты берут числа отсюда, а не
      # считают их заново и не разбирают markdown.
      def metrics
        coverage = template_view.coverage
        # Сверки может не быть (профиль без спецификации): NilClass#to_h
        # даёт пустой хеш, поэтому отдельная ветка не нужна.
        { coverage_percent: coverage.percent, covered: coverage.covered, total: coverage.total }
          .merge(checks.to_h)
      end
    end
  end
end
