# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Строка статуса провайдера → внутренний статус платформы. Одна логика
    # для enum поля статуса, для значений в примерах и для событий вебхука:
    # StatusAnalyzer и WebhookAnalyzer обязаны читать `completed` одинаково.
    #
    # Порядок доверия: расширение overlay `x-specgen-status-map` на поле,
    # затем канон кейса (уверенность 1.0 — подтверждён экспертами), затем
    # синонимы rules/statuses.yml (0.9), затем ничего: неоднозначный статус
    # из раздела `ambiguous` и незнакомый статус оба остаются невыведенными,
    # но с разным обоснованием, потому что человеку решать их по-разному.
    #
    # Событие вебхука `payout.completed` читается как статус после снятия
    # префикса: строка сравнивается целиком, затем без ведущих токенов, пока
    # не совпадёт. Полное имя всегда первым, поэтому `in_progress` никогда
    # не превратится в `progress`.
    class StatusReader
      # Что получилось из одной строки.
      #
      #   derived  Derived<Symbol> внутренний статус, либо не выведено
      #   kind     :overlay | :canonical | :synonym | :ambiguous | :unknown
      #   status   строка, которая совпала (без префикса события), либо
      #            исходная
      Result = Struct.new(:derived, :kind, :status, keyword_init: true)

      EXTENSION = 'x-specgen-status-map'
      CANONICAL_CONFIDENCE = 1.0

      # @param book [Rules::StatusesBook]
      # @param overrides [Object] значение `x-specgen-status-map` поля:
      #   {статус провайдера => внутренний статус}
      def initialize(book:, overrides: nil)
        @book = book
        @overrides = overrides.is_a?(Hash) ? overrides.to_h { |k, v| [Rules::Normalizer.call(k), v] } : {}
      end

      # @param value [Object] статус или событие как написано
      # @return [Result]
      def call(value)
        text = value.to_s
        override = @overrides[Rules::Normalizer.call(text)]
        return overlay(text, override) unless override.nil?

        candidates(text).each do |status|
          internal = @book.internal_for(status)
          return mapped(text, status, internal) if internal
          return ambiguous(text, status) if @book.ambiguous?(status)
        end
        result(IR::Derived.unknown(evidence: t('unknown', status: text)), :unknown, text)
      end

      private

      # "payout.completed" -> ["payout_completed", "completed"]
      def candidates(text)
        tokens = Rules::Normalizer.tokens(text)
        return [text] if tokens.empty?

        tokens.each_index.map { |from| tokens[from..].join('_') }.uniq
      end

      def overlay(text, value)
        internal = value.to_s.to_sym
        if IR::Roles::INTERNAL_STATUS.include?(internal)
          evidence = t('overlay', status: text, internal: internal)
          return result(IR::Derived.overlay(internal, evidence: evidence), :overlay, text)
        end

        evidence = t('overlay_bad', status: text, value: value.inspect,
                                    allowed: IR::Roles::INTERNAL_STATUS.join(' | '))
        result(IR::Derived.unknown(evidence: evidence), :unknown, text)
      end

      def mapped(text, status, internal)
        canonical = @book.canonical?(status)
        evidence = prefix_note(text, status) +
                   t(canonical ? 'canonical' : 'synonym', status: status, internal: internal)
        confidence = canonical ? CANONICAL_CONFIDENCE : IR::Derived::REGISTRY_CONFIDENCE
        result(IR::Derived.registry(internal, confidence: confidence, evidence: evidence),
               canonical ? :canonical : :synonym, status)
      end

      def ambiguous(text, status)
        evidence = prefix_note(text, status) +
                   t('ambiguous', status: status, reason: @book.ambiguity(status))
        result(IR::Derived.unknown(evidence: evidence), :ambiguous, status)
      end

      def result(derived, kind, status)
        Result.new(derived: derived, kind: kind, status: status)
      end

      # @return [String] пусто, если префикс снимать не пришлось
      def prefix_note(text, status)
        return '' if Rules::Normalizer.call(text) == status

        t('stripped', event: text, status: status)
      end

      def t(key, **params)
        Texts.t("analyzers.status.#{key}", **params)
      end
    end
  end
end
