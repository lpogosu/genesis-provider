# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Настоящая подпись фикстуры-уведомления: тот же профиль
      # IR::SignatureProfile, по которому сгенерирован verify_signature!,
      # и тот же секрет-заглушка, который лежит в credentials фикстур.
      #
      # Подпись считается по байтам raw_body, а не по объекту: фикстуру
      # можно скормить process_callback как есть и получить success. Метка
      # времени профиля Standard Webhooks — фиксированная (Time.now в
      # генераторе запрещён), при нужде переопределяется SPECGEN_TIMESTAMP.
      class Signing
        # Фиксированные значения профиля Standard Webhooks: идентификатор
        # доставки и метка времени 2026-01-01T00:00:00Z.
        MESSAGE_ID = 'msg_specgen_fixture'
        DEFAULT_TIMESTAMP = '1767225600'
        TIMESTAMP_ENV = 'SPECGEN_TIMESTAMP'
        # Чем заменяется каждый символ подписи в негативной фикстуре: длина
        # сохраняется, значение заведомо не совпадает.
        WRONG_CHAR = '0'

        # @param signature [Service::Signature] презентер верификатора
        # @param secret [String] секрет-заглушка из credentials фикстур
        def initialize(signature, secret)
          @signature = signature
          @secret = secret.to_s
        end

        # @return [Boolean] заголовок подписи выведен, подпись можно считать
        def known?
          @signature.known?(:header)
        end

        # @return [String] имя заголовка подписи
        def header
          @signature.value(:header).to_s
        end

        # @param raw_body [String] точные байты тела уведомления
        # @param valid [Boolean] false — негативная фикстура
        # @return [Hash{String => String}] заголовки подписи; пустой хеш,
        #   если профиль подписи не выведен
        def headers(raw_body, valid: true)
          return {} unless known?

          value = value_for(raw_body)
          result = { header => valid ? value : wrong(value) }
          result.merge!(timestamp_headers) if @signature.timestamped?
          result
        end

        # @param raw_body [String]
        # @return [String] значение заголовка целиком, вместе с префиксом
        def value_for(raw_body)
          "#{@signature.value_prefix}#{digest(signed_payload(raw_body))}"
        end

        private

        # @return [String] подписываемая строка по профилю
        def signed_payload(raw_body)
          return raw_body unless @signature.timestamped?

          [MESSAGE_ID, timestamp, raw_body].join('.')
        end

        def digest(data)
          algorithm = Service::Signature::DIGESTS.fetch(@signature.value(:algorithm))
          return OpenSSL::HMAC.hexdigest(algorithm, @secret, data) if hex?

          [OpenSSL::HMAC.digest(algorithm, @secret, data)].pack('m0')
        end

        def hex?
          @signature.value(:encoding) == :hex
        end

        # Префикс значения ("v1,") остаётся на месте: неверна только подпись.
        def wrong(value)
          prefix = @signature.value_prefix.to_s
          "#{prefix}#{value.delete_prefix(prefix).gsub(/./, WRONG_CHAR)}"
        end

        def timestamp_headers
          profile = @signature.profile
          { profile&.id_header.to_s => MESSAGE_ID,
            profile&.timestamp_header.to_s => timestamp }.reject { |name, _| name.empty? }
        end

        def timestamp
          ENV.fetch(TIMESTAMP_ENV, DEFAULT_TIMESTAMP)
        end
      end
    end
  end
end
