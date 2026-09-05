# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Приватные методы сервиса: сборка payload, заголовки запроса, разбор
      # ответа, перевод статуса, ключ идемпотентности (UUID v5 по RFC 4122
      # через Digest::SHA1, без SecureRandom), константное сравнение
      # подписи. Всё, что не часть протокола провайдера (ретраи, очереди,
      # алерты), здесь не реализуется: это инфраструктура платформы.
      class Privates
        INDENT = 6

        # @param ctx [Context]
        # @param parts [Hash{Symbol => Object}] payload, polling, callback,
        #   signature, authorization — презентеры, чьи строки здесь нужны
        def initialize(ctx, parts)
          @ctx = ctx
          @parts = parts
        end

        # @return [Array<Method>] в фиксированном порядке
        def methods
          [build_payload, *requisites_method, *@parts[:extras].payload_methods, request_headers,
           *@parts[:authorization].methods, *accept_methods,
           apply_internal_status, fixed(:map_status), provider_failure,
           fixed(:platform_failure_code), fixed(:parse_json), fixed(:compact_payload),
           to_provider_units, idempotency_key_for, fixed(:uuid_v5), *webhook_methods]
        end

        private

        # Реквизиты получателя отдельным методом — только если ветка по
        # request_method вообще сгенерирована.
        def requisites_method
          [@parts[:requisites].method].compact
        end

        # Разбор успешного ответа. Их два: создание обязано вернуть
        # платформе идентификатор операции у провайдера, а отмена и
        # подтверждение — нет, статус там меняют хелперы. Метод, которым
        # никто не пользуется, не печатается: мёртвый код в сгенерированном
        # файле — повод не доверять генератору.
        def accept_methods
          list = []
          list << accept_created unless @ctx.create_operation.nil?
          list << accept_response if @parts[:extras].accepting?
          list
        end

        # Приватные методы уведомлений. Спецификация без вебхуков не получает
        # ни верификатора подписи, ни разбора цели: process_callback в этом
        # случае и так отказывает, а мёртвый код в сгенерированном файле —
        # лишний повод не доверять генератору.
        def webhook_methods
          return [] if @ctx.profile.webhooks.empty?

          [@parts[:signature].unpack_method, *signature_matches, fixed(:header_value),
           fixed(:secure_equal?), callback_target]
        end

        def fixed(name)
          params, body = Snippets::FIXED.fetch(name)
          method(name.to_s, params, "#{name.to_s.delete('?')}_doc", body)
        end

        # Цель уведомления: операция платформы, если платформа отдала сервису
        # поиск, иначе идентификатор из тела уведомления — по ответу
        # экспертов от 5 сентября 2026 хранилище живёт вне сервиса.
        def callback_target
          callback = @parts[:callback]
          key = callback.lookup? ? 'callback_lookup_doc' : 'callback_target_doc'
          method('callback_target', [callback.local], key, callback.target_lines)
        end

        def method(name, params, doc_key, body, **params_for_doc)
          Method.new(name: name, params: params.map { |p| { name: p } },
                     doc: Ruby.comment(@ctx.t(doc_key, **params_for_doc), width: Ruby::WIDTH - 4),
                     body: body)
        end

        def build_payload
          schema = @ctx.create_operation&.request_schema
          lines = @parts[:payload].lines(schema, requisites: @parts[:requisites])
          body = if lines.nil? then todo('payload_schema_missing') + ['compact_payload({})']
                 else Ruby.assign_hash('payload', lines) + ['compact_payload(payload)']
                 end
          method('build_payload', payload_params, 'build_payload_doc', body, schema: schema.to_s)
        end

        # request_method доходит до тела запроса только тогда, когда из него
        # выбирается ветка реквизитов; иначе параметр там не нужен.
        def payload_params
          @parts[:requisites].branching? ? %w[operation request_method] : ['operation']
        end

        def request_headers
          media = Ruby.str(@ctx.create_operation&.request_media_type || IR::Operation::JSON)
          auth = @ctx.helper(:auth_headers)
          unless @ctx.profile.idempotency&.supported?
            return method('request_headers', [], 'request_headers_plain_doc',
                          ["#{auth}.merge('Content-Type' => #{media})"])
          end

          body = ["#{auth}.merge('Content-Type' => #{media},",
                  "#{' ' * (auth.size + 7)}IDEMPOTENCY_HEADER => idempotency_key_for(operation))"]
          method('request_headers', ['operation'], 'request_headers_doc', body)
        end

        # Успешный ответ на отмену или подтверждение: перевести статус, если
        # он пришёл и знаком. Результата у этих методов нет — статус меняют
        # хелперы апрува и реджекта.
        def accept_response
          lines = ["internal = map_status(#{status_expression})",
                   "return #{@ctx.success} if internal.nil?", '',
                   'apply_internal_status(operation, internal)']
          method('accept_response', %w[operation body], 'accept_response_doc', lines)
        end

        # Успешный ответ на создание: платформа забирает идентификатор
        # операции у провайдера как payload.dig(:result, :id), поэтому голого
        # success ей мало (эксперты кейса, 5 сентября 2026, вопрос 19).
        # Сохраняет идентификатор платформа, вне сервиса провайдера.
        def accept_created
          lines = ["apply_internal_status(operation, map_status(#{status_expression}))"]
          method('accept_created', %w[operation body], 'accept_created_doc',
                 lines + created_result)
        end

        # Результат создания: идентификатор провайдера из разобранного тела
        # по роли provider_operation_id. Роли в схеме успеха нет — вернуть
        # платформе нечего, и об этом говорит TODO, а не тишина.
        def created_result
          path = response_path(:provider_operation_id)
          success = path && @ctx.platform.create_success(@ctx.dig('body', path))
          return todo('provider_id_unknown') + [@ctx.success] if success.nil?

          [success]
        end

        # Путь к полю с ролью в успешных ответах операции создания.
        def response_path(role)
          @ctx.create_operation&.success_responses&.each do |response|
            path = @ctx.role_path(response.schema, role)
            return path if path
          end
          nil
        end

        def status_expression
          @ctx.dig('body', @parts[:polling].status_path || response_path(:status) || ['status'])
        end

        # Аргумент называется target, а не operation: в колбэке это может
        # быть идентификатор из уведомления, а не операция платформы.
        def apply_internal_status
          whens = @ctx.contract.internal_statuses.filter_map do |status|
            helper = @ctx.contract.helper_for_status(status)
            helper && "when #{Ruby.sym(status)} then #{helper}(target)"
          end
          body = whens.empty? ? [@ctx.success] : ['case internal', *whens, 'end', @ctx.success]
          method('apply_internal_status', %w[target internal], 'apply_internal_status_doc', body)
        end

        # Отказ по ответу провайдера. Первым аргументом уходит код платформы,
        # а не наше действие: действие остаётся политикой обработки в
        # ERROR_MAP и RETRY_POLICY и участвует в выборе кода, когда HTTP-кода
        # нет в таблице.
        def provider_failure
          path = @ctx.error_code_path
          failure = @ctx.helper(:failure)
          call = 'platform_failure_code(response.status, action)'
          lines = if path
                    ["code = #{@ctx.dig('body', path)}",
                     'action = ERROR_MAP[code] || ERROR_MAP[response.status] || ' \
                     'DEFAULT_ERROR_ACTION',
                     "#{failure}(#{call}, \"errors.\#{code || response.status}\")"]
                  else
                    ['action = ERROR_MAP[response.status] || DEFAULT_ERROR_ACTION',
                     "#{failure}(#{call}, \"errors.http_\#{response.status}\")"]
                  end
          method('provider_failure', %w[response body], 'provider_failure_doc', lines)
        end

        def to_provider_units
          minor = @ctx.profile.units&.unit&.value == :minor
          body = [minor ? '(amount * AMOUNT_MULTIPLIER).round' : 'amount * AMOUNT_MULTIPLIER']
          method('to_provider_units', ['amount'], 'to_provider_units_doc', body)
        end

        def idempotency_key_for
          external = @ctx.profile.idempotency&.strategy&.value == :external_id
          id = @ctx.accessor(:external_id) || 'operation'
          uuid = "uuid_v5(IDEMPOTENCY_NAMESPACE, \"\#{PROVIDER}:\#{#{id}}\")"
          body = [external ? "#{id}.to_s" : uuid]
          method('idempotency_key_for', ['operation'], 'idempotency_key_doc', body, id: id)
        end

        def signature_matches
          return [] unless @parts[:signature].value_prefix

          [method('signature_matches?', %w[expected given], 'signature_matches_doc',
                  Snippets::MATCHES)]
        end

        def todo(key)
          Ruby.comment(@ctx.t(key), width: Ruby::WIDTH - INDENT, prefix: '# TODO: ')
        end

        def note(key, **params)
          Ruby.comment(@ctx.t(key, **params), width: Ruby::WIDTH - INDENT)
        end
      end
    end
  end
end
