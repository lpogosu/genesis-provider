# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Метод опроса статуса: запрос по идентификатору операции у провайдера,
      # map_status, обработка отсутствия операции и незнакомого статуса.
      class Polling
        INDENT = 6
        NOT_FOUND = 404
        # Код отказа, когда спецификация не описывает операцию опроса.
        MISSING_CODE = :status_not_supported

        # @param ctx [Context]
        # @param http [Http]
        def initialize(ctx, http)
          @ctx = ctx
          @http = http
          @spec = ctx.contract.method_for(:fetch_status)
          @operation = ctx.status_operation
        end

        # @return [Method, nil]
        def method
          return nil if @spec.nil?

          Method.new(name: @spec.name, params: @spec.params, doc: doc, body: body)
        end

        # Путь к полю статуса в успешном ответе операции опроса.
        # @return [Array<String>, nil]
        def status_path
          return nil if @operation.nil?

          @operation.success_responses.each do |response|
            path = @ctx.role_path(response.schema, :status)
            return path if path
          end
          nil
        end

        private

        def doc
          Ruby.comment(@spec.purpose.to_s, width: Ruby::WIDTH - 4) +
            @spec.params.map { |param| "# @param #{param[:name]} [Object]" } +
            ["# @return [Object] #{@spec.returns}"]
        end

        def body
          return missing if @operation.nil?

          url, todos = @http.url(@operation)
          lines = todos + [url, @http.request(@operation), 'body = parse_json(response.body)']
          lines.concat(guard(@ctx.failure(:operation_not_found), "response.status == #{NOT_FOUND}"))
          lines.concat(guard('provider_failure(response, body)', @http.success_check(@operation),
                             negate: true))
          lines + ['', *status_lines]
        end

        def status_lines
          path = status_path
          lines = path ? [] : todo(@ctx.t('status_field_unknown'))
          lines + ["internal = map_status(#{@ctx.dig('body', path || ['status'])})",
                   *guard(@ctx.failure(:status_unknown), 'internal.nil?'), '',
                   'apply_internal_status(operation, internal)']
        end

        def guard(action, condition, negate: false)
          Ruby.guard(action, condition, indent: INDENT, negate: negate)
        end

        def missing
          todo(@ctx.t('status_missing')) + [@ctx.failure(MISSING_CODE)]
        end

        def todo(text)
          Ruby.comment(text, width: Ruby::WIDTH - INDENT, prefix: '# TODO: ')
        end
      end
    end
  end
end
