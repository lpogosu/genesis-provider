# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Верификатор подписи вебхука по IR::SignatureProfile: заголовок,
      # алгоритм, кодировка, подписываемая строка, секрет, допуск. Сравнение
      # — только OpenSSL.fixed_length_secure_compare, защищённое от разной
      # длины. Отсутствующий заголовок — отказ, а не исключение.
      #
      # Невыведенный параметр получает лучшее значение по умолчанию и TODO;
      # без заголовка метод всегда отказывает, но генерируется — молча
      # пропускать уведомления нельзя.
      class Signature
        INDENT = 6
        DIGESTS = { hmac_sha256: 'SHA256', hmac_sha512: 'SHA512', hmac_sha1: 'SHA1' }.freeze
        DEFAULTS = { algorithm: :hmac_sha256, encoding: :hex, payload: :raw_body,
                     secret_key: 'webhook_secret', header: nil, tolerance: nil }.freeze
        # Как значение члена профиля превращается в литерал константы.
        CASTS = { algorithm: ->(value) { DIGESTS.fetch(value) },
                  secret_key: :to_sym.to_proc }.freeze
        TIMESTAMP_CHECK = '(Time.now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE'
        # Код отказа на неверную подпись; его же ждёт негативная фикстура
        # уведомления в fixtures.json.
        INVALID_CODE = :signature_invalid

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @profile = ctx.webhook&.signature
        end

        # @return [Array<Array(String, String, Array<String>)>] имя константы,
        #   литерал и комментарии над ней
        def constants
          list = [constant('SIGNATURE_HEADER', :header),
                  constant('SIGNATURE_ALGORITHM', :algorithm),
                  constant('SIGNATURE_SECRET_KEY', :secret_key)]
          list.concat(timestamp_constants) if timestamped?
          list << ['SIGNATURE_VALUE_PREFIX', Ruby.str(value_prefix), []] if value_prefix
          list
        end

        # @return [Method]
        def method
          Method.new(name: 'verify_signature!', params: [{ name: 'raw_body' }, { name: 'headers' }],
                     doc: doc, body: body)
        end

        # @return [Boolean] подпись включает идентификатор и метку времени
        def timestamped?
          value(:payload) == :id_timestamp_body
        end

        # @return [String, nil] префикс значения заголовка ("v1,")
        def value_prefix
          return nil if @profile.nil? || !@profile.standard?

          @ctx.rules.signatures.default&.dig(:value_prefix)
        end

        # Значение члена профиля, с которым сгенерирован верификатор: из IR,
        # если выведено, иначе значение по умолчанию (то же, что в коде).
        # @param member [Symbol] один из DEFAULTS.keys
        # @return [Object, nil]
        def value(member)
          derived = @profile&.public_send(member)
          derived&.known? ? derived.value : DEFAULTS.fetch(member)
        end

        # @param member [Symbol]
        # @return [Boolean] член выведен из спецификации или справочника, а
        #   не взят по умолчанию
        def known?(member)
          @profile&.public_send(member)&.known? || false
        end

        # @return [IR::SignatureProfile, nil]
        attr_reader :profile

        private

        def doc
          Ruby.comment(@ctx.t('signature_doc'), width: Ruby::WIDTH - 4) +
            ['# @param raw_body [String]', '# @param headers [Hash]',
             "# @return [Object, nil] #{@ctx.t('signature_returns')}"]
        end

        def body
          lines = absent_lines + ['given = header_value(headers, SIGNATURE_HEADER)',
                                  *guard(:signature_missing, 'given.nil?'), '']
          lines.concat(timestamp_lines) if timestamped?
          check = guard(INVALID_CODE, "#{matcher}(expected, given)", negate: true)
          lines + ['secret = provider.credentials[SIGNATURE_SECRET_KEY]', "expected = #{digest}",
                   *check, '', 'nil']
        end

        def guard(code, condition, negate: false)
          Ruby.guard(@ctx.failure(code), condition, indent: INDENT, negate: negate)
        end

        def absent_lines
          return [] if @profile&.header&.known?

          key = @profile.nil? ? 'signature_absent' : 'signature_header_unknown'
          Ruby.comment(@ctx.t(key), width: Ruby::WIDTH - INDENT, prefix: '# TODO: ')
        end

        def timestamp_lines
          ['timestamp = header_value(headers, SIGNATURE_TIMESTAMP_HEADER)',
           *guard(:signature_missing, 'timestamp.nil?'),
           *guard(:signature_expired, TIMESTAMP_CHECK),
           'signed = [header_value(headers, SIGNATURE_ID_HEADER), timestamp, raw_body]' \
           ".join('.')", '']
        end

        def digest
          data = timestamped? ? 'signed' : 'raw_body'
          if value(:encoding) == :hex
            "OpenSSL::HMAC.hexdigest(SIGNATURE_ALGORITHM, secret, #{data})"
          else
            "[OpenSSL::HMAC.digest(SIGNATURE_ALGORITHM, secret, #{data})].pack('m0')"
          end
        end

        def matcher
          value_prefix ? 'signature_matches?' : 'secure_equal?'
        end

        def timestamp_constants
          [['SIGNATURE_ID_HEADER', Ruby.literal(@profile&.id_header), []],
           ['SIGNATURE_TIMESTAMP_HEADER', Ruby.literal(@profile&.timestamp_header), []],
           constant('SIGNATURE_TOLERANCE', :tolerance)]
        end

        # Константа из члена профиля: значение с обоснованием, иначе значение
        # по умолчанию с TODO.
        def constant(name, member)
          derived = @profile&.public_send(member)
          known = derived&.known?
          raw = known ? derived.value : DEFAULTS.fetch(member)
          raw = CASTS[member].call(raw) if raw && CASTS.key?(member)
          [name, Ruby.literal(raw), known ? comment(derived.evidence) : todo(member, derived)]
        end

        def todo(member, derived)
          evidence = derived&.evidence || @ctx.t('signature_absent')
          comment(@ctx.t('signature_member_unknown', member: member, evidence: evidence),
                  prefix: '# TODO: ')
        end

        def comment(text, prefix: '# ')
          Ruby.comment(text, width: Ruby::WIDTH - 4, prefix: prefix)
        end
      end
    end
  end
end
