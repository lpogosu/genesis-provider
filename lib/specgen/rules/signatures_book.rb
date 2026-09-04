# frozen_string_literal: true

module SpecGen
  module Rules
    # Именованные профили подписи вебхуков. Провайдер ссылается на профиль,
    # а не пересказывает параметры HMAC заново, и профиль по умолчанию —
    # открытая спецификация Standard Webhooks.
    #
    # У двух форм подписываемого тела требования противоположны, и справочник
    # проверяется в обе стороны: `id_timestamp_body` требует заголовок
    # идентификатора, заголовок метки времени и допуск на повтор, а `raw_body`
    # не должен их нести — допуск при теле без метки времени читался бы как
    # защита от повтора, которой на самом деле нет.
    class SignaturesBook < Book
      FILE = 'signatures.yml'
      # CLAUDE.md делает Standard Webhooks профилем по умолчанию, поэтому он
      # обязан быть в справочнике.
      DEFAULT_PROFILE = 'standard_webhooks'
      TIMESTAMPED = %i[id_header timestamp_header tolerance].freeze
      TOLERANCE_RANGE = (1..86_400)
      # Закрытый набор и ключ названия элемента для каждого поля профиля.
      VOCABULARY = {
        'profile' => [IR::SignatureProfile::PROFILES, :signature_profile],
        'algorithm' => [IR::SignatureProfile::ALGORITHMS, :signature_algorithm],
        'encoding' => [IR::SignatureProfile::ENCODINGS, :signature_encoding],
        'payload' => [IR::SignatureProfile::PAYLOADS, :signature_payload]
      }.freeze

      # @return [Array<String>] нормализованные имена заголовков, несущих
      #   подпись: из `header_names` и из самих профилей
      attr_reader :headers

      # @param name [String] имя профиля
      # @return [Hash, nil] профиль с символьными ключами
      def profile(name)
        @profiles[name.to_s]
      end

      # @return [Hash, nil] профиль Standard Webhooks
      def default
        @profiles[DEFAULT_PROFILE]
      end

      # @return [Array<String>] имена профилей, в порядке справочника
      def names
        @profiles.keys
      end

      # @param header [String] имя заголовка, встреченное в спецификации
      # @return [Boolean]
      def signature_header?(header)
        @headers.include?(Normalizer.call(header))
      end

      private

      def build
        @profiles = {}
        section('profiles').each { |name, body| add(name, body) }
        check_default
        @headers = collect_headers
        [@profiles, @headers].each(&:freeze)
      end

      def check_default
        return if default

        fault('signatures.default_missing', path('profiles'), profile: DEFAULT_PROFILE)
      end

      def add(name, body)
        at = path('profiles', name)
        fields = mapping(body, noun(:profile_body, name: name), at)
        entry = vocabularies(fields, at).merge(literals(fields, at))
        check_replay(entry, fields, at)
        @profiles[name.to_s] = entry.freeze
      end

      # Поля профиля, которые берутся как написаны, без закрытого словаря.
      def literals(fields, at)
        { header: text(fields['header'], noun(:signature_header), "#{at}.header"),
          secret_key: text(fields['secret_key'], noun(:secret_key), "#{at}.secret_key"),
          value_prefix: fields['value_prefix'], source: fields['source'] }
      end

      def vocabularies(fields, at)
        VOCABULARY.to_h do |key, (allowed, what)|
          [key.to_sym, symbol_in(fields[key], allowed, noun(what), "#{at}.#{key}")]
        end
      end

      def check_replay(entry, fields, at)
        TIMESTAMPED.each { |key| entry[key] = fields[key.to_s] }
        return check_timestamped(entry, at) if entry[:payload] == :id_timestamp_body

        present = TIMESTAMPED.select { |key| entry[key] }
        return if present.empty?

        fault('signatures.replay_not_applicable', at, keys: present.join(', '))
      end

      def check_timestamped(entry, at)
        entry[:id_header] = text(entry[:id_header], noun(:id_header), "#{at}.id_header")
        entry[:timestamp_header] = text(entry[:timestamp_header], noun(:timestamp_header),
                                        "#{at}.timestamp_header")
        entry[:tolerance] = integer(entry[:tolerance], noun(:tolerance), "#{at}.tolerance",
                                    range: TOLERANCE_RANGE)
      end

      def collect_headers
        declared = string_list(data['header_names'], noun(:list, key: 'header_names'),
                               path('header_names'))
        from_profiles = @profiles.values.filter_map { |entry| entry[:header] }
        (declared + from_profiles).map { |header| Normalizer.call(header) }
                                  .reject(&:empty?).uniq.sort
      end
    end
  end
end
