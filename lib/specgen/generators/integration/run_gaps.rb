# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 9, часть третья: допущения прогона на уровне профиля —
      # единицы суммы, профиль подписи, код конфликта, авторизация,
      # статусы и события без пары, действия по ошибкам по умолчанию, роли
      # операций ниже порога, песочница. Каждое из них стало значением по
      # умолчанию или TODO в коде.
      class RunGaps < Base
        # @return [Array<String>]
        def lines
          units_lines + signature_lines + idempotency_lines + auth_lines + status_lines +
            error_lines + operation_lines + server_lines
        end

        private

        def units_lines
          units = profile.units
          return [] if units.nil?
          # Обоснование у члена, которого не хватило: см. IR::Units#blocker.
          return [t('run_units_unknown', evidence: units.blocker.evidence)] unless units.known?

          members = [units.unit, units.exponent, units.currency].select { |d| ctx.doubtful?(d) }
          members.map { |d| t('run_units_doubt', confidence: label(d), evidence: d.evidence) }
        end

        def signature_lines
          webhook = ctx.webhook
          return [] if webhook.nil?
          return [t('run_signature_absent')] if webhook.signature.nil?

          webhook.signature.missing.map do |member|
            t('run_signature_member', member: member, evidence: webhook.signature[member].evidence,
                                      value: code(parts[:signature].value(member).inspect))
          end
        end

        def idempotency_lines
          idempotency = profile.idempotency
          return [t('run_idempotency_none')] if idempotency.nil? && ctx.create_operation
          return [] if idempotency.nil? || idempotency.dedup?

          [t('run_dedup_unknown', evidence: idempotency.conflict_status.evidence)]
        end

        def auth_lines
          auth = profile.auth
          return [t('run_auth_none')] if auth.nil? || auth.none?
          return [] if parts[:authorization].recognised?

          [t('run_auth_unknown', scheme: auth.scheme_name)]
        end

        def status_lines
          statuses = parts[:tables].status_mappings.reject { |m| m.internal.known? }
          events = parts[:tables].events.reject(&:mapped?)
          statuses.map { |m| t('run_status_unmapped', status: m.provider_status) } +
            events.map { |e| t('run_event_unmapped', event: e.name) }
        end

        def error_lines
          rules = parts[:tables].code_rules + parts[:tables].http_rules
          rules.select { |r| ctx.doubtful?(r.action) }.map { |rule| error_line(rule) }
        end

        def error_line(rule)
          t('run_error_doubt', code: rule.provider_code || rule.http_status,
                               action: code(rule.action.value), confidence: label(rule.action))
        end

        def operation_lines
          profile.operations.filter_map do |operation|
            role = operation.role
            if operation.unmapped?
              t('run_operation_unmapped', key: operation.key)
            elsif ctx.doubtful?(role)
              t('run_operation_doubt', key: operation.key, role: role.value,
                                       confidence: label(role))
            end
          end
        end

        def server_lines
          return [] if profile.servers.any?(&:sandbox?)

          [t('run_sandbox', url: ctx.sandbox_url)]
        end
      end
    end
  end
end
