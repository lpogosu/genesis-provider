# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 3: таблица методов с идемпотентностью. Строки — методы
      # контракта в порядке rules/contract.yml, затем операции вне контракта
      # из Service::Extras. Сигнатуры — те же Method, что напечатаны в
      # сервисе.
      class Methods < Base
        HEADERS_KEYS = %w[method_col endpoint_col request_method_col idempotency_col
                          result_col].freeze

        # @return [Array<String>] заголовки таблицы
        def headers
          HEADERS_KEYS.map { |key| t(key) }
        end

        # @return [Array<Array<String>>] по строке на метод контракта
        def contract_rows
          parts[:view].contract_methods.map { |method| contract_row(method) }
        end

        # @return [Array<Array<String>>] операции вне контракта
        def extra_rows
          parts[:extras].entries.map { |operation, method| extra_row(operation, method) }
        end

        private

        # Что метод обслуживает: роли из справочника решают, какая это строка.
        def kind_of(spec)
          return :check if spec.roles.empty?
          return :callback if spec.roles.include?('webhook')
          return :status if spec.roles.include?('fetch_status')

          :create
        end

        def contract_row(method)
          spec = contract.method_spec(method.name)
          kind = kind_of(spec)
          [code(method.signature), endpoint_cell(kind), request_method_cell(spec),
           idempotency_cell(kind), result_cell(kind)]
        end

        def operation_of(kind)
          case kind
          when :create then ctx.create_operation
          when :status then ctx.status_operation
          when :callback then profile.operation_for(:webhook)
          end
        end

        def endpoint_cell(kind)
          return t('method_no_http') if kind == :check
          return incoming_cell if kind == :callback

          operation = operation_of(kind)
          return endpoint(operation) if operation

          t('method_missing', failure: failure(missing_code(kind)), report: report)
        end

        # Входящий вебхук: операция из paths, иначе путь вебхука, объявленного
        # вне paths, иначе — не описан.
        def incoming_cell
          operation = operation_of(:callback)
          endpoint = operation ? endpoint(operation) : webhook_endpoint
          return t('method_incoming', endpoint: endpoint) if endpoint

          t('method_missing', failure: failure(missing_code(:callback)), report: report)
        end

        def webhook_endpoint
          ctx.webhook && code("POST #{ctx.webhook.path}")
        end

        def missing_code(kind)
          { create: Service::Creation::MISSING_CODE, status: Service::Polling::MISSING_CODE,
            callback: Service::Callback::MISSING_CODE }.fetch(kind)
        end

        def request_method_cell(spec)
          param = spec.params.find { |item| item[:name] == 'request_method' }
          return t('request_method_none') if param.nil?
          return t('request_method_default', value: code(param[:default])) if param[:default]

          t('request_method_any', values: codes(contract.request_method_values))
        end

        def idempotency_cell(kind)
          case kind
          when :check then t('idem_check')
          when :create then create_idempotency
          when :callback then t('idem_callback')
          else operation_of(:status)&.http_method == :get ? t('idem_get') : t('none')
          end
        end

        def create_idempotency
          idempotency = profile.idempotency
          return t('idem_header_none', report: report) unless idempotency&.supported?

          conflict = idempotency.conflict_status
          text = if conflict.known? then t('idem_conflict_known', status: conflict.value)
                 else t('idem_conflict_unknown', report: report)
                 end
          t('idem_create', header: code(idempotency.header.value), conflict: text)
        end

        def result_cell(kind)
          case kind
          when :check then check_result
          when :callback
            t('result_callback', approve: code(ctx.helper(:approve_operation)),
                                 reject: code(ctx.helper(:reject_operation)), **names)
          else t("result_#{kind}", **names)
          end
        end

        # У предпроверок один код платформы на всех: набор проверок открыт,
        # он растёт с каждым ограничением спецификации. Что именно не
        # сошлось, говорит ключ локализации вторым аргументом.
        def check_result
          precheck = parts[:precheck]
          keys = precheck.conditions.filter_map { |item| precheck.failure_code(item) }.uniq
          return t('result_check_plain', **names) if keys.empty?

          t('result_check', code: validation_code,
                            codes: codes(keys.map { |key| "errors.#{key}" }), **names)
        end

        def validation_code
          code(":#{contract.platform.failure_codes.validation}")
        end

        def extra_row(operation, method)
          role = if operation.unmapped? then t('extra_unmapped')
                 else t('extra_role', role: operation.role.value, confidence: label(operation.role))
                 end
          key = operation.role.value == :cancel ? 'result_extra_cancel' : 'result_extra_body'
          ["#{code(method.signature)} — #{role}", endpoint(operation), t('request_method_none'),
           extra_idempotency(operation), t(key, **names)]
        end

        # @return [Hash] подстановки success / failure / result для текстов
        #   результата: платформа читает идентификатор созданной операции
        #   как payload.dig(:result, :id)
        def names
          { success: code(ctx.helper(:success)), failure: code(ctx.helper(:failure)),
            result: code(result_read) }
        end

        # @return [String] как платформа достаёт идентификатор из результата
        def result_read
          success = contract.platform.create_success('…')
          success ? 'payload.dig(:result, :id)' : t('none')
        end

        def extra_idempotency(operation)
          header = operation.parameters_in(:header).find { |p| p.role.value == :idempotency_key }
          return t('idem_extra_header', header: code(header.name)) if header
          return t('idem_get') if operation.http_method == :get

          t('none')
        end
      end
    end
  end
end
