# frozen_string_literal: true

module SpecGen
  module IR
    # Как проверяется подпись вебхука. Профиль по умолчанию — Standard
    # Webhooks; всё остальное — :custom, и каждый параметр приходится выводить
    # отдельно, а полностью такое спецификации описывают редко. Поэтому
    # каждый параметр — Derived, по умолчанию не выведенный, а `missing`
    # перечисляет то, о чём отчёт обязан спросить.
    #
    #   profile           Derived<Symbol> :standard_webhooks | :custom
    #   header            Derived<String> — имя заголовка с подписью
    #   algorithm         Derived<Symbol>, один из ALGORITHMS
    #   encoding          Derived<Symbol> :hex | :base64
    #   payload           Derived<Symbol> :raw_body | :id_timestamp_body
    #   tolerance         Derived<Integer> — окно защиты от повтора в
    #                     секундах; нужно только тогда, когда в подписываемое
    #                     тело входит метка времени
    #   secret_key        Derived<String> — ключ в provider.credentials
    #   id_header         заголовок идентификатора доставки для
    #                     :id_timestamp_body, иначе nil
    #   timestamp_header  заголовок метки времени для :id_timestamp_body,
    #                     иначе nil
    #   json_path         где подпись задокументирована
    SignatureProfile = Struct.new(:profile, :header, :algorithm, :encoding, :payload, :tolerance,
                                  :secret_key, :id_header, :timestamp_header, :json_path,
                                  keyword_init: true)

    # Словарь значений, значения по умолчанию и полнота SignatureProfile.
    class SignatureProfile
      include Node

      PROFILES = %i[standard_webhooks custom].freeze
      ALGORITHMS = %i[hmac_sha256 hmac_sha512 hmac_sha1].freeze
      ENCODINGS = %i[hex base64].freeze
      PAYLOADS = %i[raw_body id_timestamp_body].freeze
      # Поля, которые обязаны быть выведены, прежде чем можно генерировать
      # верификатор.
      REQUIRED = %i[profile header algorithm encoding payload secret_key].freeze
      UNDERIVED = 'не выведено'

      # @param profile [Derived]
      # @param header [Derived]
      # @param algorithm [Derived]
      # @param encoding [Derived]
      # @param payload [Derived]
      # @param tolerance [Derived]
      # @param secret_key [Derived]
      # @param id_header [String, nil]
      # @param timestamp_header [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(profile: Derived.unknown(evidence: UNDERIVED),
                     header: Derived.unknown(evidence: UNDERIVED),
                     algorithm: Derived.unknown(evidence: UNDERIVED),
                     encoding: Derived.unknown(evidence: UNDERIVED),
                     payload: Derived.unknown(evidence: UNDERIVED),
                     tolerance: Derived.unknown(evidence: UNDERIVED),
                     secret_key: Derived.unknown(evidence: UNDERIVED),
                     id_header: nil, timestamp_header: nil, json_path: nil)
        Node.assert_derived!(profile, 'профиль подписи', allowed: PROFILES)
        Node.assert_derived!(header, 'заголовок подписи')
        Node.assert_derived!(algorithm, 'алгоритм подписи', allowed: ALGORITHMS)
        Node.assert_derived!(encoding, 'кодирование подписи', allowed: ENCODINGS)
        Node.assert_derived!(payload, 'подписываемое тело', allowed: PAYLOADS)
        Node.assert_derived!(tolerance, 'допуск на повтор')
        Node.assert_derived!(secret_key, 'ключ секрета подписи')
        super
      end

      # @return [Array<Symbol>] поля, которые ещё не выведены, в порядке
      #   объявления
      def missing
        needed = REQUIRED.dup
        needed << :tolerance if payload.value == :id_timestamp_body
        needed.reject { |member| self[member].known? }
      end

      # @return [Boolean] верификатор можно сгенерировать без TODO
      def complete?
        missing.empty?
      end

      # @return [Boolean]
      def standard?
        profile.value == :standard_webhooks
      end
    end
  end
end
