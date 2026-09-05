# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Метод обработки уведомления: проверка подписи до любой другой логики,
      # затем цель уведомления — идентификатор операции у провайдера, иначе
      # внешний (он может быть необязательным в схеме), — затем перевод
      # события во внутренний статус по EVENT_MAP, где перечислены все
      # события из enum; незнакомое событие — отказ, а не тишина.
      #
      # Аргумент — уже разобранный JSON (эксперты кейса, 5 сентября 2026),
      # поэтому здесь нет ни разбора тела, ни поиска операции в хранилище:
      # работа с хранилищем происходит вне сервиса провайдера. Если
      # rules/contract.yml задаёт выражения поиска, они возвращаются в
      # сгенерированный код без правки шаблона.
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

        # Выражение с разобранным телом уведомления.
        # @return [String]
        def payload
          @ctx.platform.callback_body || param
        end

        # Имя переменной с разобранным телом внутри метода: сам аргумент,
        # если контракт не оборачивает тело, иначе локальная переменная. Её
        # же имя носит аргумент callback_target.
        # @return [String]
        def local
          payload == param ? param : 'body'
        end

        # @return [Boolean] платформа отдала сервису поиск операции
        def lookup?
          !@ctx.platform.roles(:lookup).empty?
        end

        # Строки, вычисляющие цель уведомления: идентификаторы из тела, а
        # если платформа отдала сервису поиск операции — её выражения.
        # @return [Array<String>]
        def target_lines
          expressions = LOOKUP_ROLES.filter_map do |role|
            path = @ctx.role_path(@webhook&.schema, role)
            next nil if path.nil?

            value = @ctx.dig(local, path)
            @ctx.platform.lookup(role, value) || value
          end
          return todo(@ctx.t('target_unknown')) + ['nil'] if expressions.empty?
          return [expressions.join(' || ')] if fits?(expressions)

          joined = expressions.join(" ||\n  ")
          joined.split("\n")
        end

        private

        # Помещается ли перечисление идентификаторов в одну строку тела
        # метода (отступ INDENT), чтобы не переносить его без нужды.
        def fits?(expressions)
          INDENT + expressions.join(' || ').length <= Ruby::WIDTH
        end

        def doc
          Ruby.comment(@spec.purpose.to_s, width: Ruby::WIDTH - 4) +
            @spec.params.map { |param| "# @param #{param[:name]} [Object]" } +
            ["# @return [Object] #{@spec.returns}"]
        end

        def body
          return missing if @webhook.nil?

          shape_lines + ["problem = verify_signature!(#{param})",
                         'return problem if problem', ''] + unwrap_lines +
            ["target = callback_target(#{local})",
             *guard(:operation_not_found, 'target.nil?'), '',
             *status_lines, '', 'apply_internal_status(target, internal)']
        end

        # Форма аргумента задана в rules/contract.yml; её отсутствие не молчит.
        def shape_lines
          return [] if @ctx.platform.callback_body

          todo(@ctx.t('callback_shape', param: param))
        end

        # Разобранное тело в локальную переменную, если контракт говорит, что
        # аргумент его оборачивает.
        def unwrap_lines
          local == param ? [] : ["#{local} = #{payload}", '']
        end

        def param
          @spec.params.first[:name]
        end

        def status_lines
          event_expression + guard(UNKNOWN_EVENT_CODE, 'internal.nil?')
        end

        def event_expression
          field = event_field
          return ["internal = EVENT_MAP[#{@ctx.dig(local, [field.name])}]"] if field

          path = @ctx.role_path(@webhook.schema, :status)
          return ["internal = map_status(#{@ctx.dig(local, path)})"] if path

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
