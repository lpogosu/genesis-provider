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
        UUID_V5 = [
          "digest = Digest::SHA1.digest([namespace.delete('-')].pack('H*') + name.to_s)",
          'bytes = digest.bytes[0, 16]',
          'bytes[6] = (bytes[6] & 0x0f) | 0x50', 'bytes[8] = (bytes[8] & 0x3f) | 0x80',
          "hex = bytes.pack('C*').unpack1('H*')",
          "[hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')"
        ].freeze
        PARSE_JSON = ['parsed = JSON.parse(text.to_s)', 'parsed.is_a?(Hash) ? parsed : {}',
                      'rescue JSON::ParserError', '{}'].freeze
        COMPACT = ['return value unless value.is_a?(Hash)', '',
                   'value.transform_values { |item| compact_payload(item) }.compact'].freeze
        HEADER_VALUE = ['return nil if name.nil? || headers.nil?', '',
                        'headers.find { |key, _value| key.to_s.casecmp?(name) }&.last'].freeze
        SECURE_EQUAL = ['return false unless expected.to_s.bytesize == given.to_s.bytesize', '',
                        'OpenSSL.fixed_length_secure_compare(expected.to_s, given.to_s)'].freeze
        MATCHES = ['given.split.any? do |item|',
                   '  secure_equal?(expected, item.delete_prefix(SIGNATURE_VALUE_PREFIX))',
                   'end'].freeze
        # Методы с постоянным телом: имя, параметры, ключ текста, строки.
        FIXED = {
          map_status: [['raw'], ['STATUS_MAP[raw.to_s]']],
          parse_json: [['text'], PARSE_JSON],
          compact_payload: [['value'], COMPACT],
          uuid_v5: [%w[namespace name], UUID_V5],
          header_value: [%w[headers name], HEADER_VALUE],
          secure_equal?: [%w[expected given], SECURE_EQUAL]
        }.freeze

        # @param ctx [Context]
        # @param parts [Hash{Symbol => Object}] payload, polling, callback,
        #   signature, authorization — презентеры, чьи строки здесь нужны
        def initialize(ctx, parts)
          @ctx = ctx
          @parts = parts
        end

        # @return [Array<Method>] в фиксированном порядке
        def methods
          [build_payload, request_headers, *@parts[:authorization].methods, accept_response,
           apply_internal_status, fixed(:map_status), provider_failure, fixed(:parse_json),
           fixed(:compact_payload), to_provider_units, idempotency_key_for, fixed(:uuid_v5),
           @parts[:signature].method, *signature_matches, fixed(:header_value),
           fixed(:secure_equal?), find_callback_operation]
        end

        private

        def fixed(name)
          params, body = FIXED.fetch(name)
          method(name.to_s, params, "#{name.to_s.delete('?')}_doc", body)
        end

        def find_callback_operation
          method('find_callback_operation', ['body'], 'find_callback_operation_doc',
                 @parts[:callback].lookup_lines)
        end

        def method(name, params, doc_key, body, **params_for_doc)
          Method.new(name: name, params: params.map { |p| { name: p } },
                     doc: Ruby.comment(@ctx.t(doc_key, **params_for_doc), width: Ruby::WIDTH - 4),
                     body: body)
        end

        def build_payload
          schema = @ctx.create_operation&.request_schema
          lines = @parts[:payload].lines(schema)
          body = if lines.nil? then todo('payload_schema_missing') + ['compact_payload({})']
                 else ['payload = {', *Ruby.indent(lines, 2), '}', 'compact_payload(payload)']
                 end
          method('build_payload', ['operation'], 'build_payload_doc', body, schema: schema.to_s)
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

        # Успешный ответ на создание или отмену: запомнить идентификатор
        # провайдера, перевести статус, если он пришёл и знаком.
        def accept_response
          lines = remember_lines + ["internal = map_status(#{status_expression})",
                                    "return #{@ctx.success} if internal.nil?", '',
                                    'apply_internal_status(operation, internal)']
          method('accept_response', %w[operation body], 'accept_response_doc', lines)
        end

        def remember_lines
          path = response_path(:provider_operation_id)
          writer = path && @ctx.platform.writer(:provider_operation_id, 'provider_id')
          return todo('provider_id_unknown') if writer.nil?

          ["provider_id = #{@ctx.dig('body', path)}", "#{writer} if provider_id"]
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

        def apply_internal_status
          whens = @ctx.contract.internal_statuses.filter_map do |status|
            helper = @ctx.contract.helper_for_status(status)
            helper && "when #{Ruby.sym(status)} then #{helper}(operation)"
          end
          body = whens.empty? ? [@ctx.success] : ['case internal', *whens, 'end', @ctx.success]
          method('apply_internal_status', %w[operation internal], 'apply_internal_status_doc', body)
        end

        def provider_failure
          path = @ctx.error_code_path
          failure = @ctx.helper(:failure)
          lines = if path
                    ["code = #{@ctx.dig('body', path)}",
                     'action = ERROR_MAP[code] || ERROR_MAP[response.status] || ' \
                     'DEFAULT_ERROR_ACTION',
                     "#{failure}(action, \"errors.\#{code || response.status}\")"]
                  else
                    ['action = ERROR_MAP[response.status] || DEFAULT_ERROR_ACTION',
                     "#{failure}(action, \"errors.http_\#{response.status}\")"]
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
          uuid = "uuid_v5(IDEMPOTENCY_NAMESPACE, \"\#{PROVIDER}:\#{operation.id}\")"
          body = [external ? 'operation.id.to_s' : uuid]
          method('idempotency_key_for', ['operation'], 'idempotency_key_doc', body)
        end

        def signature_matches
          return [] unless @parts[:signature].value_prefix

          [method('signature_matches?', %w[expected given], 'signature_matches_doc', MATCHES)]
        end

        def todo(key)
          Ruby.comment(@ctx.t(key), width: Ruby::WIDTH - INDENT, prefix: '# TODO: ')
        end
      end
    end
  end
end
