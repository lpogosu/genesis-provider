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
    # префикса: строка сравнивается целиком, затем без ведущих сегментов,
    # пока не совпадёт. Полное имя всегда первым, поэтому `in_progress`
    # никогда не превратится в `progress`.
    #
    # Адресом считается только то, что отделено разделителем сегмента
    # (`.`, `:`, `/`): такой префикс снимается молча и уверенность не
    # понижает. Ведущие слова внутри самого имени — другое дело, и решают их
    # два правила из rules/statuses.yml:
    #
    #   modifiers        слово, меняющее смысл статуса за ним. `PART_DONE`
    #                    читается как `DONE`, только если забыть про `PART`,
    #                    а частично проведённый платёж не выплачен. Такая
    #                    строка остаётся невыведенной с видом :partial, и
    #                    обоснование называет хвост, чтобы человеку было что
    #                    закрепить в overlay. Ровно за этим
    #                    `partially_completed` лежит в `ambiguous`.
    #   tail_confidence  всё остальное: `authAdjustmentRefused` читается как
    #                    `refused`, но ниже порога матчеров — отброшенные
    #                    слова могли значить что-то важное, и это чтение
    #                    обязано попасть в отчёт как допущение прогона.
    #   suffixes         хвост, который исхода не меняет: `capturedExternally`
    #                    — это `captured`, проведённый вне платформы
    #                    провайдера. Слово снимается, остаток читается заново
    #                    с той же пониженной уверенностью.
    #   heads            голова, по которой читается всё имя, когда хвост не
    #                    прочитался: `AwaitingFurtherAuthorisation`,
    #                    `AcceptedWithoutPosting` (открытый банкинг
    #                    Великобритании). Справочник разрешает в этом списке
    #                    только слова, отображённые в in_progress, поэтому
    #                    правило по построению не может пометить
    #                    невыплаченные деньги как выплаченные.
    #   not_status_words слово, по которому видно, что значение называет ТИП
    #                    операции, а не исход (`bankTransfer`, `fee`,
    #                    `BALANCE_INQUIRY` в одном enum со статусами).
    #                    Внутреннего статуса не даёт никогда — только
    #                    предупреждение о том, что enum смешанный.
    class StatusReader
      # Что получилось из одной строки.
      #
      #   derived  Derived<Symbol> внутренний статус, либо не выведено
      #   kind     :overlay | :canonical | :synonym | :ambiguous | :tail |
      #            :suffix | :head | :partial | :not_status | :unknown
      #   status   строка, которая совпала (без префикса события), либо
      #            исходная
      Result = Struct.new(:derived, :kind, :status, keyword_init: true) do
        # @return [Boolean] строка прочитана как статус, пусть и спорный;
        #   :partial сюда не входит — совпал только хвост слова
        def read?
          !UNREAD.include?(kind)
        end
      end

      EXTENSION = 'x-specgen-status-map'
      CANONICAL_CONFIDENCE = 1.0
      # Разделители адреса события: `payout.completed`, `payout:completed`,
      # `payout/completed`. Всё остальное — разделители внутри имени статуса.
      SEGMENT = %r{[.:/]}
      # Виды результата, при которых статус не прочитан.
      UNREAD = %i[partial not_status unknown].freeze

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

        addressed(text) || inner(text) || stripped(text) || headed(text) || typed(text) ||
          result(IR::Derived.unknown(evidence: t('unknown', status: text)), :unknown, text)
      end

      private

      # @return [Array<String>] токены последнего сегмента адреса события
      def name_tokens(text)
        Rules::Normalizer.tokens(text.to_s.split(SEGMENT).last.to_s)
      end

      # Имя целиком, затем без ведущих сегментов адреса:
      # "payout.completed" -> ["payout_completed", "completed"].
      # @return [Result, nil]
      def addressed(text)
        candidates(text).each do |status|
          internal = @book.internal_for(status)
          return mapped(text, status, internal) if internal
          return ambiguous(text, status) if @book.ambiguous?(status)
        end
        nil
      end

      def candidates(text)
        full = Rules::Normalizer.call(text)
        return [text] if full.empty?

        segments = text.to_s.split(SEGMENT).reject { |part| Rules::Normalizer.call(part).empty? }
        return [full] if segments.size < 2

        ([full] + segments.each_index.map do |from|
          Rules::Normalizer.call(segments[from..].join('_'))
        end).uniq
      end

      # Хвост внутри одного сегмента: `authAdjustmentRefused` -> `refused`
      # читается с пониженной уверенностью, `PART_DONE` -> `DONE` не
      # читается вовсе — `PART` стоит в modifiers rules/statuses.yml.
      # @return [Result, nil]
      def inner(text)
        tokens = name_tokens(text)
        (1...tokens.size).each do |from|
          tail = tokens[from..].join('_')
          internal = @book.internal_for(tail)
          return ambiguous(text, tail) if internal.nil? && @book.ambiguous?(tail)
          next if internal.nil?

          word = @book.modifier(tokens.take(from))
          return word ? partial(text, tail, internal, word) : tailed(text, tail, internal)
        end
        nil
      end

      # Снимаем хвост, который исхода не меняет, и читаем остаток:
      # `capturedExternally` -> `captured`. Уверенность понижена, как у
      # любого чтения по части имени.
      # @return [Result, nil]
      def stripped(text)
        tokens = name_tokens(text)
        word = @book.suffix(tokens)
        return nil if word.nil?

        rest = tokens[0..-2].join('_')
        internal = @book.internal_for(rest)
        return ambiguous(text, rest) if internal.nil? && @book.ambiguous?(rest)
        return nil if internal.nil?

        evidence = t('suffix', status: text, suffix: word, tail: rest, internal: internal)
        result(heuristic(internal, evidence), :suffix, rest)
      end

      # Голова составного имени: `AwaitingUpload` -> `awaiting`. Справочник
      # держит в `heads` только слова, отображённые в in_progress, поэтому
      # худшее, что делает это правило, — оставляет операцию в опросе.
      # @return [Result, nil]
      def headed(text)
        tokens = name_tokens(text)
        return nil if tokens.size < 2

        word = @book.head(tokens)
        internal = word && @book.internal_for(word)
        return nil if internal.nil?

        evidence = t('head', status: text, head: word, internal: internal)
        result(heuristic(internal, evidence), :head, word)
      end

      # Значение называет тип операции, а не её исход: внутреннего статуса
      # нет, но человеку сказано, почему.
      # @return [Result, nil]
      def typed(text)
        word = @book.type_word(name_tokens(text))
        return nil if word.nil?

        evidence = t('not_status', status: text, word: word)
        result(IR::Derived.unknown(evidence: evidence), :not_status, text)
      end

      def heuristic(internal, evidence)
        IR::Derived.heuristic(internal, confidence: @book.tail_confidence, evidence: evidence)
      end

      def partial(text, tail, internal, word)
        evidence = t('partial', status: text, tail: tail, internal: internal, word: word)
        result(IR::Derived.unknown(evidence: evidence), :partial, text)
      end

      def tailed(text, tail, internal)
        evidence = t('tail', status: text, tail: tail, internal: internal)
        result(heuristic(internal, evidence), :tail, tail)
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
