# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Метод обработки уведомления: проверка подписи до любой другой логики,
      # поиск операции сначала по идентификатору провайдера, потом по
      # внешнему (он может быть необязательным в схеме уведомления), затем
      # перевод события во внутренний статус по EVENT_MAP, где перечислены
      # все события из enum; незнакомое событие — отказ, а не тишина.
      class Callback
        INDENT = 6
        LOOKUP_ROLES = %i[provider_operation_id external_id].freeze
        # Код отказа, когда спецификация не описывает вебхуков.
        MISSING_CODE = :webhooks_not_supported
        # Код отказа на событие, которого нет в enum; его же ждёт негативная
        # фикстура уведомления в fixtures.json.
        UNKNOWN_EVENT_CODE = :unknown_event

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @spec = ctx.contract.method_for(:webhook)
          @webhook = ctx.webhook
        end

        # @return [Method, nil]
        def method
          return nil if @spec.nil?

          Method.new(name: @spec.name, params: @spec.params, doc: doc, body: body)
        end

        # Поле уведомления, чьи значения — имена событий.
        # @return [IR::Field, nil]
        def event_field
          return nil if @webhook.nil? || @webhook.events.empty?

          names = @webhook.events.map(&:name)
          schema = @ctx.schema(@webhook.schema)
          schema&.fields&.find { |field| field.enum && (names - field.enum).empty? }
        end

        # Строки поиска операции по идентификаторам из тела уведомления.
        # @return [Array<String>]
        def lookup_lines
          expressions = LOOKUP_ROLES.filter_map do |role|
            path = @ctx.role_path(@webhook&.schema, role)
            path && @ctx.platform.lookup(role, @ctx.dig('body', path))
          end
          return todo(@ctx.t('lookup_unknown')) + ['nil'] if expressions.empty?

          joined = expressions.join(" ||\n  ")
          joined.split("\n")
        end

        private

        def doc
          Ruby.comment(@spec.purpose.to_s, width: Ruby::WIDTH - 4) +
            @spec.params.map { |param| "# @param #{param[:name]} [Object]" } +
            ["# @return [Object] #{@spec.returns}"]
        end

        def body
          return missing if @webhook.nil?

          unpack_lines +
            ['problem = verify_signature!(raw_body, headers)', 'return problem if problem', '',
             'body = parse_json(raw_body)', 'operation = find_callback_operation(body)',
             *guard(:operation_not_found, 'operation.nil?'), '',
             *status_lines, '', 'apply_internal_status(operation, internal)']
        end

        # Сырое тело и заголовки из аргумента — выражения платформы.
        def unpack_lines
          platform = @ctx.platform
          param = @spec.params.first[:name]
          lines = platform.callback_body ? [] : todo(@ctx.t('callback_shape', param: param))
          lines + ["raw_body = #{platform.callback_body || param}.to_s",
                   "headers = #{platform.callback_headers || '{}'} || {}"]
        end

        def status_lines
          event_expression + guard(UNKNOWN_EVENT_CODE, 'internal.nil?')
        end

        def event_expression
          field = event_field
          return ["internal = EVENT_MAP[body[#{Ruby.str(field.name)}]]"] if field

          path = @ctx.role_path(@webhook.schema, :status)
          return ["internal = map_status(#{@ctx.dig('body', path)})"] if path

          todo(@ctx.t('event_field_unknown')) + ['internal = nil']
        end

        def guard(code, condition)
          Ruby.guard(@ctx.failure(code), condition, indent: INDENT)
        end

        def missing
          todo(@ctx.t('webhook_missing')) + [@ctx.failure(MISSING_CODE)]
        end

        def todo(text)
          Ruby.comment(text, width: Ruby::WIDTH - INDENT, prefix: '# TODO: ')
        end
      end
    end
  end
end
