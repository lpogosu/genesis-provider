# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Покрытие спецификации сгенерированной интеграцией: семь измерений и
      # одна цифра.
      #
      # Формула — доля покрытых элементов от всех: сумма покрытого по всем
      # измерениям, делённая на сумму найденного. Среднее по измерениям
      # отброшено намеренно: измерения разного размера, и четыре события
      # вебхука не должны весить столько же, сколько триста полей.
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

        # @return [Array<Array(String, String)>] всё непокрытое с причиной
        def gaps
          dimensions.flat_map(&:gaps)
        end

        private

        def build(key, total, gaps)
          Dimension.new(key: key, total: total, covered: total - gaps.size, gaps: gaps)
        end

        # Операция покрыта, если у неё есть метод сервиса: метод контракта
        # либо отдельный публичный метод. Роль :unmapped покрытием не
        # считается — метод сгенерирован, но что он делает, решает человек.
        def operations
          gaps = profile.operations.select(&:unmapped?).map do |operation|
            [operation.key, t('gap_operation_unmapped')]
          end
          build('operations', profile.operations.size, gaps)
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
