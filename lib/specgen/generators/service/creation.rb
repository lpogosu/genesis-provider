# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Метод создания операции: сборка payload по ролям, отправка, разбор
      # ответа. Отдельная ветка — успешный путь дедупликации: ответ с кодом
      # конфликта, чья схема совпадает со схемой успеха, обрабатывается как
      # успех с подхватом существующей операции. Это требование
      # draft-ietf-httpapi-idempotency-key-header, не наша выдумка.
      class Creation
        INDENT = 6
        ACCEPT = 'accept_created(operation, body)'
        # Код отказа, когда спецификация не описывает операцию создания.
        MISSING_CODE = :create_not_supported

        # @return [IR::Operation, nil]
        attr_reader :operation

        # @param ctx [Context]
        # @param http [Http]
        # @param requisites [Requisites] реквизиты получателя: от них зависит,
        #   получает ли сборка тела запроса request_method
        def initialize(ctx, http, requisites)
          @ctx = ctx
          @http = http
          @requisites = requisites
          @spec = ctx.contract.method_for(:create_payout) ||
                  ctx.contract.method_for(:create_deposit)
          @operation = ctx.create_operation
        end

        # @return [Method, nil]
        def method
          return nil if @spec.nil?

          Method.new(name: @spec.name, params: @spec.params, doc: doc, body: body)
        end

        # @return [Boolean] у профиля есть код дедупликации
        def dedup?
          @ctx.profile.idempotency&.dedup? || false
        end

        private

        def doc
          lines = Ruby.comment(@spec.purpose.to_s, width: Ruby::WIDTH - 4)
          unless other_creates.empty?
            lines.concat(Ruby.comment(@ctx.t('create_other', keys: other_creates.join(', ')),
                                      width: Ruby::WIDTH - 4))
          end
          lines + @spec.params.map { |param| "# @param #{param[:name]} [Object]" } +
            ["# @return [Object] #{@spec.returns}"]
        end

        # Вторая операция создания (депозит рядом с выплатой) в метод не
        # попадает: контракт даёт один метод; о ней говорит комментарий.
        def other_creates
          creates = @ctx.profile.operations_by_role(:create_payout) +
                    @ctx.profile.operations_by_role(:create_deposit)
          creates.reject { |op| op.equal?(@operation) }.map(&:key)
        end

        def body
          return missing if @operation.nil?

          url, todos = @http.url(@operation)
          request = @http.request(@operation, payload: 'payload', headers: headers)
          args = @requisites.branching? ? 'operation, request_method' : 'operation'
          lines = todos + ["payload = build_payload(#{args})", url, request,
                           'body = parse_json(response.body)']
          lines.concat(Ruby.guard(ACCEPT, @http.success_check(@operation), indent: INDENT))
          lines + dedup_lines + ['', 'provider_failure(response, body)']
        end

        def headers
          @ctx.profile.idempotency&.supported? ? 'request_headers(operation)' : 'request_headers'
        end

        def dedup_lines
          return [] unless dedup?

          Ruby.comment(@ctx.t('dedup'), width: Ruby::WIDTH - INDENT) +
            Ruby.guard(ACCEPT, 'response.status == DEDUP_STATUS', indent: INDENT)
        end

        def missing
          Ruby.comment(@ctx.t('create_missing'), width: Ruby::WIDTH - INDENT, prefix: '# TODO: ') +
            [@ctx.failure(MISSING_CODE)]
        end
      end
    end
  end
end
