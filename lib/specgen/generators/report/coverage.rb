# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Покрытие спецификации сгенерированной интеграцией: семь измерений и
      # две цифры.
      #
      # Формула — доля покрытых элементов от всех: сумма покрытого по всем
      # измерениям, делённая на сумму найденного. Среднее по измерениям
      # отброшено намеренно: измерения разного размера, и четыре события
      # вебхука не должны весить столько же, сколько триста полей.
      #
      # Вторая цифра — та же доля, но от знаменателя, из которого вычтено
      # то, чему в методах контракта нет места по построению: поля входящих
      # тел с ролью вне читаемых, необязательные поля запросов без роли и
      # операции без собственного метода. Первая отвечает «сколько
      # спецификации задействовано», вторая — «сколько задействовано из
      # того, что контракт вообще может использовать». Исключается только
      # непокрытое и только по этим трём правилам; всё остальное —
      # коды ответов, статусы, события, условия, обязательные поля запросов
      # — остаётся в знаменателе, даже когда не покрыто.
      #
      # Покрытым считается элемент, у которого есть ветка, выражение или
      # строка таблицы в сгенерированном коде. Всё остальное перечисляется
      # поимённо с причиной: измеренная граница полезнее круглой цифры.
      class Coverage < Base
        # Чем проверяется покрытие условия каждого вида, кроме проверяемых до
        # запроса: те закрывает Service::Precheck::CHECKED.
        COVERAGE_CHECKS = {
          cancel_status_restriction: :cancel_covered?, retry_after: :retry_after_covered?,
          rate_limited: :rate_limit_covered?, idempotency_optional: :idempotency_covered?
        }.freeze

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}]
        def initialize(ctx, parts)
          super
          @fields = CoverageFields.new(ctx, parts)
        end

        # @return [Array<Dimension>] в порядке разделов отчёта
        def dimensions
          @dimensions ||= [operations, @fields.request, @fields.response, response_codes,
                           statuses, events, conditions]
        end

        # @return [Integer] элементов спецификации найдено
        def total
          dimensions.sum(&:total)
        end

        # @return [Integer] из них задействовано в сгенерированном коде
        def covered
          dimensions.sum(&:covered)
        end

        # @return [Integer] покрытие в процентах
        def percent
          return 100 if total.zero?

          ((covered.to_f / total) * 100).round
        end

        # @return [Integer] элементов вычтено из знаменателя второй цифры
        def out_of_scope
          dimensions.sum(&:excluded)
        end

        # @return [Integer] элементов, которые контракт способен использовать
        def in_scope_total
          total - out_of_scope
        end

        # @return [Integer] покрытие в границах контракта, в процентах
        def in_scope_percent
          return 100 if in_scope_total.zero?

          ((covered.to_f / in_scope_total) * 100).round
        end

        # @return [Array<Dimension>] измерения, что-то отдавшие в исключение
        def excluded_dimensions
          dimensions.reject { |dimension| dimension.excluded.zero? }
        end

        # @return [Array<Array(String, String)>] всё непокрытое с причиной
        def gaps
          dimensions.flat_map(&:gaps)
        end

        private

        def build(key, total, gaps, out_of_scope: 0)
          Dimension.new(key: key, total: total, covered: total - gaps.size, gaps: gaps,
                        out_of_scope: out_of_scope)
        end

        # Операция покрыта, если у неё есть метод сервиса: метод контракта
        # либо отдельный публичный метод. Роль :unmapped покрытием не
        # считается — метод сгенерирован, но что он делает, решает человек.
        #
        # Из знаменателя второй цифры уходит только операция, которой не
        # досталось даже отдельного метода: пока Extras генерирует метод
        # каждой операции вне контракта, таких нет, и исключение остаётся
        # нулевым — это проверка, а не скидка.
        def operations
          unmapped = profile.operations.select(&:unmapped?)
          gaps = unmapped.map { |operation| [operation.key, t('gap_operation_unmapped')] }
          build('operations', profile.operations.size, gaps,
                out_of_scope: unmapped.count { |operation| !own_method?(operation) })
        end

        def own_method?(operation)
          parts[:extras].entries.any? { |extra, _method| extra.equal?(operation) }
        end

        # Ответы входящего вебхука не считаются: их пишем мы, а не провайдер.
        def response_codes
          entries = code_entries
          gaps = entries.reject { |operation, response| code_covered?(operation, response) }
                        .map { |operation, response| code_gap(operation, response) }
          build('response_codes', entries.size, gaps)
        end

        def code_entries
          profile.operations.reject { |operation| operation.role.value == :webhook }
                 .flat_map { |operation| operation.responses.map { |r| [operation, r] } }
        end

        def code_covered?(operation, response)
          status = response.code
          return true if response.success?
          return false if status.nil?

          status == dedup_status || http_statuses.include?(status) ||
            specific_statuses(operation).include?(status)
        end

        def dedup_status
          idempotency = profile.idempotency
          idempotency&.dedup? ? idempotency.conflict_status.value : nil
        end

        def http_statuses
          @http_statuses ||= tables.http_rules.map(&:http_status)
        end

        def specific_statuses(operation)
          tables.specific_rules.select { |rule| rule.operation == operation.key }
                .map(&:http_status)
        end

        def code_gap(operation, response)
          element = "#{operation.key} #{response.status}"
          reason = response.code.nil? ? t('gap_code_range') : t('gap_code_default')
          [element, reason]
        end

        def statuses
          mappings = tables.status_mappings
          gaps = mappings.reject { |mapping| mapping.internal.known? }
                         .map { |mapping| [mapping.provider_status, t('gap_status')] }
          build('statuses', mappings.size, gaps)
        end

        def events
          all = tables.events
          gaps = all.reject(&:mapped?).map { |event| [event.name, t('gap_event')] }
          build('events', all.size, gaps)
        end

        def conditions
          all = profile.conditions
          gaps = all.reject { |condition| condition_covered?(condition) }
                    .map { |condition| [condition_label(condition), condition_reason(condition)] }
          build('conditions', all.size, gaps)
        end

        def condition_covered?(condition)
          return checked?(condition) if Service::Precheck::CHECKED.include?(condition.kind)

          check = COVERAGE_CHECKS[condition.kind]
          check ? send(check, condition) : false
        end

        def cancel_covered?(_condition)
          !parts[:extras].cancellable_statuses.nil?
        end

        def retry_after_covered?(condition)
          tables.retry_after_statuses.include?(condition.value.value)
        end

        def rate_limit_covered?(_condition)
          !tables.retry_policy[:statuses].empty?
        end

        def idempotency_covered?(_condition)
          profile.idempotency&.supported? == true
        end

        # Условие покрыто, если в check_conditions есть проверка с тем же
        # видом, ролью и значением: Precheck схлопывает побайтово одинаковые
        # проверки двух полей одной роли, и обе они покрыты одним guard'ом.
        def checked?(condition)
          precheck = parts[:precheck]
          # Значение задано по построению (константа валюты, литерал способа
          # выплаты в своей ветке): проверять нечего, но и пробелом это не
          # является — ограничение спецификации соблюдено самим кодом.
          return true if precheck.constant?(condition)
          return false if precheck.failure_code(condition).nil?

          precheck.conditions.any? { |item| same_check?(item, condition, precheck) }
        end

        def same_check?(item, condition, precheck)
          item.kind == condition.kind && item.value.value == condition.value.value &&
            precheck.role_of(item) == precheck.role_of(condition)
        end

        def condition_label(condition)
          [condition.kind, condition.field || condition.operation].compact.join(' ')
        end

        def condition_reason(condition)
          unless Service::Precheck::CHECKED.include?(condition.kind)
            return t("gap_condition_#{condition.kind}")
          end
          if parts[:precheck].in_requisites?(condition)
            return t('gap_condition_in_requisites', field: condition.field,
                                                    method: parts[:requisites].method_name)
          end

          t('gap_condition_no_check', field: condition.field)
        end
      end
    end
  end
end
