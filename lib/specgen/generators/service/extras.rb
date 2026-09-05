# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Операции вне контракта BaseService: отмена, подтверждение, возврат,
      # баланс и всё, что не отобразилось ни на одну роль (`:unmapped`).
      # Каждая — отдельный публичный метод с пометкой «не отображено на
      # контракт»; unmapped — метод по operationId или пути с TODO. Ничего не
      # выбрасывается молча.
      #
      # Тело запроса такая операция собирает по ролям тем же презентером
      # Payload, что и операция создания: у каждой появляется свой приватный
      # build_<метод>_payload. Раньше здесь стоял пустой хеш с TODO, и на
      # чужих спецификациях это съедало покрытие полей запросов — у Adyen
      # Transfers 81 поле из 97 не попадало в код только потому, что операция
      # не та.
      class Extras
        INDENT = 6
        # Роли операций, которые получают отдельный метод.
        EXTRA_ROLES = %i[cancel confirm refund balance unmapped].freeze
        # Роли, чей ответ относится к той же операции платформы: статус из
        # него переводится во внутренний. Возврат создаёт новую операцию,
        # поэтому в список не входит — его тело просто возвращается.
        ACCEPTING_ROLES = %i[cancel confirm].freeze
        # Naming/AccessorMethodName: метод без аргументов не может
        # называться get_*.
        GETTER = /\Aget_/

        # @param ctx [Context]
        # @param http [Http]
        def initialize(ctx, http)
          @ctx = ctx
          @http = http
          @taken = ctx.contract.method_names +
                   Rules::ContractBook::HELPERS.map { |helper| ctx.helper(helper) } +
                   [ctx.parts_requisites&.method_name].compact
        end

        # @return [Array<Method>] в порядке операций спецификации
        def methods
          entries.map(&:last)
        end

        # @return [Array<Array(IR::Operation, Method)>] операция и метод,
        #   который для неё сгенерирован, в порядке спецификации
        def entries
          @entries ||= operations.map { |op| [op, build(op)] }
        end

        # Приватные сборщики тела запроса — по одному на операцию со схемой
        # тела, в том же порядке.
        # @return [Array<Method>]
        def payload_methods
          operations.filter_map { |operation| payload_method(operation) }
        end

        # @param operation [IR::Operation]
        # @return [String, nil] имя сборщика тела для этой операции
        def payload_builder(operation)
          name = names[operation.key]
          return nil if name.nil? || operation.request_schema.nil?

          "build_#{name}_payload"
        end

        # @return [Boolean] есть операция, чей успешный ответ разбирает
        #   accept_response: отмена или подтверждение той же операции
        def accepting?
          operations.any? { |op| ACCEPTING_ROLES.include?(op.role.value) }
        end

        # Операции вне контракта в порядке спецификации.
        # @return [Array<IR::Operation>]
        def operations
          @operations ||= @ctx.profile.operations
                              .select { |op| EXTRA_ROLES.include?(op.role.value) }
        end

        # Имена методов считаются одним проходом и до тел: тело операции
        # ссылается на имя её же сборщика payload, и вычислять имена лениво
        # изнутри тела значило бы звать самого себя.
        # @return [Hash{String => String}] ключ операции → имя метода
        def names
          @names ||= operations.to_h { |op| [op.key, method_name(op, params(op))] }
        end

        # Внутренние статусы, в которых отмена возможна, по ограничению из
        # спецификации; nil, если ограничения нет.
        # @return [Array<Symbol>, nil]
        def cancellable_statuses
          return nil if restriction.nil?

          statuses = Array(restriction.value.value).map(&:to_s)
          mapped = @ctx.profile.status_map.select(&:mapped?)
          allowed = mapped.select { |m| statuses.include?(m.provider_status) }
          allowed.map { |m| m.internal.value }.uniq
        end

        private

        def restriction
          @ctx.profile.conditions.find { |c| c.kind == :cancel_status_restriction }
        end

        def build(operation)
          params = params(operation)
          Method.new(name: names[operation.key], params: params,
                     doc: doc(operation, params), body: body(operation))
        end

        def method_name(operation, params)
          role = operation.role.value
          base = role == :unmapped ? Ruby.snake(operation.key) : role.to_s
          base = base.sub(GETTER, '') if params.empty? && base.match?(GETTER)
          name = @taken.include?(base) || base.empty? ? "#{base}_request" : base
          @taken << name
          name
        end

        def params(operation)
          needs = !operation.parameters_in(:path).empty? || operation.request_schema
          needs ? [{ name: 'operation' }] : []
        end

        def doc(operation, params)
          role = operation.role
          lines = comment(@ctx.t('extra_doc', key: operation.key, role: role.value,
                                              confidence: @ctx.source_label(role)), 4)
          if operation.unmapped?
            lines.concat(comment(@ctx.t('unmapped_doc', evidence: role.evidence), 4, '# TODO: '))
          end
          lines + params.map { |p| "# @param #{p[:name]} [Object]" } + ['# @return [Object]']
        end

        def body(operation)
          url, todos = @http.url(operation)
          request = @http.request(operation, payload: operation.request_schema ? 'payload' : nil)
          lines = restriction_lines(operation) + todos + payload_lines(operation) +
                  [url, request, 'body = parse_json(response.body)']
          lines.concat(Ruby.guard('provider_failure(response, body)',
                                  @http.success_check(operation), indent: INDENT, negate: true))
          accepting = ACCEPTING_ROLES.include?(operation.role.value)
          lines + ['', accepting ? 'accept_response(operation, body)' : 'body']
        end

        # Отмена только в разрешённых статусах — если спецификация об этом
        # сказала и у платформы есть выражение для статуса операции.
        def restriction_lines(operation)
          status = @ctx.accessor(:status)
          return [] unless operation.role.value == :cancel && cancellable_statuses && status

          text = @ctx.t('cancel_restriction', statuses: Array(restriction.value.value).join(', '),
                                              source: @ctx.source_label(restriction.value))
          condition = "CANCELLABLE_STATUSES.include?(#{status})"
          comment(text, INDENT) +
            Ruby.guard(@ctx.failure(:cancel_not_allowed), condition, indent: INDENT, negate: true)
        end

        # Тело запроса операции вне контракта: тот же сборщик по ролям, что
        # и у операции создания, отдельным приватным методом.
        def payload_lines(operation)
          builder = payload_builder(operation)
          builder.nil? ? [] : ["payload = #{builder}(operation)"]
        end

        # @return [Method, nil]
        def payload_method(operation)
          builder = payload_builder(operation)
          return nil if builder.nil?

          schema = operation.request_schema
          lines = @ctx.parts_payload.lines(schema)
          body = Ruby.assign_hash('payload', lines) + ['compact_payload(payload)']
          Method.new(name: builder, params: [{ name: 'operation' }],
                     doc: comment(@ctx.t('extra_payload_doc', key: operation.key, schema: schema),
                                  4),
                     body: body)
        end

        def comment(text, indent, prefix = '# ')
          Ruby.comment(text, width: Ruby::WIDTH - indent, prefix: prefix)
        end
      end
    end
  end
end
