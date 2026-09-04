# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Профиль подписи одного вебхука — из его заголовков, описания,
    # rules/signatures.yml и расширения overlay `x-specgen-signature`.
    #
    # Порядок доверия. Параметр-заголовок, имя которого знает справочник
    # (`header_names`), — структурный факт. Если это же имя носит один из
    # именованных профилей, весь профиль берётся из справочника (:registry),
    # а алгоритм из описания («HMAC-SHA256») только подтверждает его или,
    # разойдясь, даёт предупреждение signature_profile_conflict. Если
    # заголовок известен, а профиля нет, — это :custom: алгоритм читается
    # из описания как эвристика, а кодирование и подписываемое тело
    # спецификации почти никогда не называют — они остаются невыведенными,
    # и предупреждение signature_profile_incomplete предлагает фрагмент
    # overlay. Standard Webhooks приходит тем же путём: его заголовок
    # `webhook-signature` — header профиля по умолчанию.
    #
    # Overlay побеждает всё: каждый член `x-specgen-signature` заменяет
    # выведенный, а значение вне словаря отвергается с предупреждением.
    class SignatureReader
      # Профиль (nil, если подписи нет и overlay её не задал) и заметки
      # [код, сообщение, JSONPath, фрагмент overlay].
      Result = Struct.new(:profile, :notes, keyword_init: true)

      EXTENSION = 'x-specgen-signature'
      ALGORITHM_CONFIDENCE = 0.7

      # @param node [Hash] Operation Object вебхука
      # @param key [String] Operation#key, для сообщений
      # @param headers [Array<Array(String, String, String)>] имя, JSONPath
      #   и описание каждого параметра-заголовка
      # @param book [Rules::SignaturesBook]
      # @param at [String] JSONPath операции — цель фрагмента overlay
      def initialize(node:, key:, headers:, book:, at:)
        @node = node
        @key = key
        @headers = headers
        @book = book
        @at = at
        @notes = []
      end

      # @return [Result]
      def call
        overlay = @node[EXTENSION].is_a?(Hash) ? @node[EXTENSION] : {}
        found = @headers.find { |name, _, _| @book.signature_header?(name) }
        return Result.new(profile: nil, notes: [missing_note]) if found.nil? && overlay.empty?

        profile = found ? from_header(*found) : custom(overlay['header'].to_s, @at, nil)
        apply_overlay(profile, overlay)
        report_incomplete(profile)
        Result.new(profile: profile, notes: @notes)
      end

      private

      def from_header(header, path, description)
        name, entry = @book.profile_for_header(header)
        return custom(header, path, description) if entry.nil?

        registry(header, path, description, name, entry)
      end

      def registry(header, path, description, name, entry)
        evidence = t('profile_evidence', name: name, header: header)
        IR::SignatureProfile.new(
          profile: IR::Derived.registry(entry[:profile], evidence: evidence),
          header: IR::Derived.structural(header, evidence: t('header_evidence', header: header)),
          algorithm: registry_algorithm(entry, evidence, description, name),
          encoding: IR::Derived.registry(entry[:encoding], evidence: evidence),
          payload: IR::Derived.registry(entry[:payload], evidence: evidence),
          tolerance: tolerance_of(entry, evidence),
          secret_key: IR::Derived.registry(entry[:secret_key], evidence: evidence),
          id_header: entry[:id_header], timestamp_header: entry[:timestamp_header], json_path: path
        )
      end

      # Описание подтверждает алгоритм профиля или противоречит ему; само по
      # себе оно алгоритм справочника не меняет.
      def registry_algorithm(entry, evidence, description, name)
        hint = @book.algorithm_hint(text_of(description))
        return IR::Derived.registry(entry[:algorithm], evidence: evidence) if hint.nil?

        hinted, words = hint
        if hinted == entry[:algorithm]
          confirmed = evidence + t('algorithm_confirmed', words: words.inspect)
          return IR::Derived.registry(entry[:algorithm], evidence: confirmed)
        end

        message = t('conflict_message', key: @key, words: words.inspect, hinted: hinted,
                                        name: name, algorithm: entry[:algorithm])
        @notes << [:signature_profile_conflict, message, @at, nil]
        IR::Derived.registry(entry[:algorithm], evidence: evidence)
      end

      def tolerance_of(entry, evidence)
        return IR::Derived.registry(entry[:tolerance], evidence: evidence) if entry[:tolerance]

        IR::Derived.unknown(evidence: t('tolerance_not_applicable'))
      end

      def custom(header, path, description)
        hint = @book.algorithm_hint(text_of(description))
        default = @book.default || {}
        IR::SignatureProfile.new(
          profile: IR::Derived.structural(:custom, evidence: t('custom_evidence', header: header)),
          header: IR::Derived.structural(header, evidence: t('header_evidence', header: header)),
          algorithm: custom_algorithm(hint),
          encoding: IR::Derived.unknown(evidence: t('encoding_unknown')),
          payload: IR::Derived.unknown(evidence: t('payload_unknown')),
          tolerance: IR::Derived.unknown(evidence: t('tolerance_unknown')),
          secret_key: default_secret(default), json_path: path
        )
      end

      def custom_algorithm(hint)
        return IR::Derived.unknown(evidence: t('algorithm_unknown')) if hint.nil?

        algorithm, words = hint
        IR::Derived.heuristic(algorithm, confidence: ALGORITHM_CONFIDENCE,
                                         evidence: t('algorithm_hint', words: words.inspect,
                                                                       algorithm: algorithm))
      end

      # Имя ключа в provider.credentials — наше соглашение, не факт
      # спецификации; берётся у профиля по умолчанию.
      def default_secret(default)
        key = default[:secret_key]
        return IR::Derived.unknown(evidence: t('secret_key_unknown')) if key.nil?

        IR::Derived.registry(key, evidence: t('secret_key_default', key: key,
                                                                    profile: Rules::SignaturesBook::DEFAULT_PROFILE))
      end

      # Описание операции, её summary и описание самого заголовка — всё, где
      # спецификация могла назвать алгоритм.
      def text_of(description)
        [@node['summary'], @node['description'], description].grep(String).join("\n")
      end

      def apply_overlay(profile, overlay)
        overlay.each do |key, value|
          member = key.to_s.to_sym
          next bad_overlay(key, value, 'x-specgen-signature keys') unless
            IR::SignatureProfile::VOCABULARY.key?(member)

          coerced = coerce(member, value)
          next bad_overlay(key, value, allowed_for(member)) if coerced.nil?

          evidence = t('overlay_evidence', key: key, value: coerced)
          profile[member] = IR::Derived.overlay(coerced, evidence: evidence)
        end
      end

      def coerce(member, value)
        allowed = IR::SignatureProfile::VOCABULARY[member]
        return value.is_a?(Integer) && value.positive? ? value : nil if member == :tolerance
        return value.is_a?(String) && !value.strip.empty? ? value.strip : nil if allowed.nil?

        symbol = value.to_s.to_sym
        allowed.include?(symbol) ? symbol : nil
      end

      def allowed_for(member)
        allowed = IR::SignatureProfile::VOCABULARY[member]
        allowed ? allowed.join(' | ') : member.to_s
      end

      def bad_overlay(key, value, allowed)
        @notes << [:spec_element_unsupported,
                   t('overlay_bad', key: key, value: value.inspect, allowed: allowed), @at, nil]
      end

      def report_incomplete(profile)
        missing = profile.missing
        return if missing.empty?

        @notes << [:signature_profile_incomplete,
                   t('incomplete_message', key: @key, missing: missing.join(', ')), @at,
                   fragment(profile)]
      end

      def fragment(profile)
        t('overlay_fragment', path: @at, header: profile.header.value || 'X-Signature',
                              algorithm: profile.algorithm.value || 'hmac_sha256',
                              secret_key: profile.secret_key.value || 'webhook_secret')
      end

      def missing_note
        [:signature_profile_incomplete, t('missing_message', key: @key), @at,
         t('overlay_fragment', path: @at, header: 'X-Signature', algorithm: 'hmac_sha256',
                               secret_key: 'webhook_secret')]
      end

      def t(key, **params)
        Texts.t("analyzers.signature.#{key}", **params)
      end
    end
  end
end
