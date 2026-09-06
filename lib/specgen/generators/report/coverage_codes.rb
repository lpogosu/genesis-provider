# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Измерение покрытия, которое считается по кодам ответов: у какого
      # объявленного кода есть в сгенерированном коде своя ветка.
      #
      # Покрытым считается успешный код, код дедупликации и код, попавший в
      # ERROR_MAP правилом по HTTP-коду или правилом операции. Действие по
      # умолчанию покрытием не считается: ветки у такого ответа нет.
      #
      # Ответы входящей точки уведомления не считаются вовсе: их пишем мы, а
      # не провайдер.
      class CoverageCodes < Base
        # @return [Dimension]
        def dimension
          gaps = entries.reject { |operation, response| covered?(operation, response) }
                        .map { |operation, response| gap(operation, response) }
          build('response_codes', entries.size, gaps)
        end

        private

        def entries
          @entries ||= outgoing.flat_map do |operation|
            operation.responses.map { |response| [operation, response] }
          end
        end

        def outgoing
          profile.operations.reject { |operation| operation.role.value == :webhook }
        end

        def covered?(operation, response)
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

        # Код, объявленный диапазоном (`default`, `2XX`), покрыть нечем: это
        # устройство спецификации, а не пропуск интеграции, — отсюда своя
        # причина и своя корзина.
        def gap(operation, response)
          key = response.code.nil? ? :gap_code_range : :gap_code_default
          Gap.new(element: "#{operation.key} #{response.status}", reason_key: key,
                  foreign: !scope.operation?(operation))
        end
      end
    end
  end
end
