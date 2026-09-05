# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 5: обработка ошибок с действиями. Строки — правила из
      # Service::Tables, те же, что в ERROR_MAP, ERROR_MAP_BY_OPERATION и
      # RETRY_POLICY; выражение отказа — то, которое собирает
      # provider_failure сервиса.
      class Errors < Base
        # @return [Array<String>] заголовки таблицы кодов провайдера
        def code_headers
          %w[code_col http_col seen_col action_col service_col].map { |key| t(key) }
        end

        # @return [Array<String>] заголовки таблицы HTTP-кодов
        def http_headers
          %w[http_col action_col service_col].map { |key| t(key) }
        end

        # @return [Array<Array<String>>] код ошибки провайдера → действие
        def code_rows
          tables.code_rules.map do |rule|
            [code(rule.provider_code), t('error_http_any'), seen(rule), action(rule),
             failure_of(rule.action.value, rule.provider_code)]
          end
        end

        # @return [Array<Array<String>>] HTTP-код → действие
        def http_rows
          tables.http_rules.map do |rule|
            [code(rule.http_status), action(rule), failure_of(rule.action.value, http_key(rule))]
          end
        end

        # @return [Array<Array<String>>] операция, HTTP-код, действие — только
        #   расхождения с общей таблицей
        def operation_rows
          tables.specific_rules.sort_by(&:sort_key).map do |rule|
            [code(rule.operation), code(rule.http_status), action(rule)]
          end
        end

        # @return [Array<Array<String>>] словарь действий, встречающихся в таблицах
        def action_rows
          actions = (tables.code_rules + tables.http_rules).map { |r| r.action.value }.uniq.sort
          actions.map { |name| [code(name), t("action_#{name}")] }
        end

        # @return [Boolean] есть хоть одно правило
        def any?
          !(tables.code_rules.empty? && tables.http_rules.empty?)
        end

        # @return [Symbol] действие по умолчанию из rules/errors.yml
        def default_action
          ctx.rules.errors.default_action
        end

        # @return [Array<String>] абзацы о политике ретраев
        def retry_lines
          policy = tables.retry_policy
          [t('retry_policy', actions: codes(policy[:actions]),
                             statuses: codes(policy[:statuses]),
                             retry_after: retry_after(policy)),
           t('retry_mechanism'),
           t('default_action', default: code(ctx.rules.errors.default_action))]
        end

        # @return [String] дедупликация — успешный путь, отдельной строкой
        def dedup_line
          idempotency = profile.idempotency
          return t('dedup_no_idempotency', report: report) if idempotency.nil?
          return t('dedup_none', report: report) unless idempotency.dedup?

          t('dedup_row', status: idempotency.conflict_status.value, operation: dedup_operation,
                         method: code(contract.method_for(:create_payout)&.name.to_s))
        end

        private

        def tables
          parts[:tables]
        end

        # Операция, у которой объявлен ответ дедупликации: по правилу с
        # действием dedup, иначе по операциям, принимающим заголовок.
        def dedup_operation
          rule = profile.sorted_error_map.find(&:dedup?)
          code(rule&.operation || profile.idempotency.operations.join(', '))
        end

        def seen(rule)
          return t('seen_both') if rule.declared? && rule.seen_in.include?(:example)
          return t('seen_enum') if rule.declared?

          t('seen_example')
        end

        def action(rule)
          text = code(rule.action.value)
          return text unless ctx.doubtful?(rule.action)

          "#{text} (#{t('action_default_note', confidence: label(rule.action))})"
        end

        def retry_after(policy)
          return t('retry_after_no') if policy[:retry_after_header].nil?

          t('retry_after_yes', header: code(policy[:retry_after_header]),
                               statuses: codes(policy[:retry_after_statuses]))
        end

        # Ключ локализации отказа по HTTP-коду: как в provider_failure —
        # errors.<код>, если тело несёт код ошибки, иначе errors.http_<код>.
        def http_key(rule)
          ctx.error_code_path ? rule.http_status.to_s : "http_#{rule.http_status}"
        end

        def failure_of(action, key)
          code("#{ctx.helper(:failure)}(#{Ruby.sym(action)}, #{Ruby.str("errors.#{key}")})")
        end
      end
    end
  end
end
