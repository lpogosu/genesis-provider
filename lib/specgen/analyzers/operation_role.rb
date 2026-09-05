# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Для чего нужен эндпоинт — решается подсчётом голосов.
    #
    # Роль операции не сообщает ни одна спецификация, и ни один отдельный
    # сигнал её не решает: `POST /payouts` может быть и выплатой, и
    # приёмником вебхука, а `payoutWebhook` называет и то и другое. Поэтому
    # каждый сигнал — operationId, хвост пути, слова ресурса в нём,
    # HTTP-метод, тег, наличие тела запроса, отсутствие авторизации —
    # голосует с тем весом, который ему даёт rules/operations.yml, и
    # побеждает роль, набравшая больше всех голосов. Это композитный матчер
    # из COMA (Rahm & Bernstein 2001), применённый к эндпоинтам вместо
    # столбцов: несколько независимых матчеров, веса, агрегация, порог.
    #
    # Уверенность — арифметика, а не ощущение: это доля победителя в весе
    # всех сигналов, которые вообще голосовали. Сигнал, который голосовать
    # не смог — в спецификации нет operationId, — не попадает в знаменатель,
    # потому что о нехватке входных данных сообщает отдельное
    # предупреждение, и она не должна молча занижать решение, принятое по
    # всему остальному.
    #
    # Ниже порога или слишком близко к следующей роли ответ — :unmapped, а
    # набранные очки сохраняются для отчёта. Догадка здесь отправила бы
    # эндпоинт отмены в `create_request`.
    class OperationRole
      # Что решил матчер и всё, что нужно отчёту, чтобы это объяснить.
      #
      #   role        победившая роль или :unmapped
      #   derived     IR::Derived с ролью, уверенностью и обоснованием
      #   reason      nil, если роль победила, иначе :no_signal,
      #               :below_threshold или :ambiguous
      #   scores      [[роль, очки]], лучшая первой
      #   cast        суммарный вес сигналов, которые голосовали
      Result = Struct.new(:role, :derived, :reason, :scores, :cast, keyword_init: true)

      TEMPLATE = /\A\{.+\}\z/
      # Сигналы, которые называют роль, а не просто сопутствуют ей.
      IDENTIFYING = %i[operation_id path_tail path_resource tag unsecured].freeze

      # Арифметика победившей роли: её голоса по сигналам, сумма и сколько
      # весов вообще проголосовало. Держатся вместе, потому что и уверенность,
      # и обоснование считаются из одной и той же тройки.
      Tally = Struct.new(:vote, :score, :cast, keyword_init: true)

      # @param book [Rules::OperationsBook] слова, веса и пороги
      # @param id [String, nil] operationId
      # @param http_method [Symbol]
      # @param path [String] шаблон пути
      # @param tags [Array<String>]
      # @param body [Boolean] операция объявляет requestBody
      # @param secured [Boolean] false, если она объявляет `security: []`
      def initialize(book:, http_method:, path:, id: nil, tags: [], body: false, secured: true)
        @book = book
        @id_tokens = Rules::Normalizer.tokens(id)
        @http_method = http_method
        @tags = Array(tags).flat_map { |tag| Rules::Normalizer.tokens(tag) }
        @body = body
        @secured = secured
        read_path(path)
      end

      # @return [Result]
      def call
        votes = book.roles.to_h { |role| [role, votes_for(role)] }
        decide(votes, cast_weight(votes))
      end

      private

      attr_reader :book

      def read_path(path)
        parts = path.to_s.split('/').reject(&:empty?)
        tail = parts.last.to_s
        @tail_parameter = tail.match?(TEMPLATE)
        @tail_tokens = @tail_parameter ? [] : Rules::Normalizer.tokens(tail)
        @segments = parts.grep_v(TEMPLATE).flat_map { |part| Rules::Normalizer.tokens(part) }
      end

      # @return [Hash{Symbol => Float}] сигнал => вес, отданный этой роли
      def votes_for(role)
        entry = book.entry(role)
        { operation_id: id_vote(entry), path_tail: tail_vote(entry),
          path_resource: resource_vote(entry), http_method: method_vote(entry),
          tag: tag_vote(entry), request_body: body_vote(entry),
          unsecured: unsecured_vote(entry) }.compact
      end

      # Глагол и существительное вместе называют роль; одно из двух в
      # одиночку — подсказка, стоящая доли веса.
      def id_vote(entry)
        return nil if @id_tokens.empty?

        verb = hit?(@id_tokens, entry[:verbs])
        noun = hit?(@id_tokens, entry[:nouns]) || hit?(@id_tokens, entry[:resources])
        return weight(:operation_id) if verb && noun
        return weight(:operation_id) * book.scoring(:partial) if verb || noun

        nil
      end

      # Путь, кончающийся шаблонным параметром, читается как обращение к
      # ресурсу; путь, кончающийся словом, — это само это слово.
      def tail_vote(entry)
        return entry[:tail_parameter] ? weight(:path_tail) : nil if @tail_parameter

        hit?(@tail_tokens, entry[:tail]) ? weight(:path_tail) : nil
      end

      def resource_vote(entry)
        hit?(@segments, entry[:resources]) ? weight(:path_resource) : nil
      end

      def method_vote(entry)
        entry[:http_methods].include?(@http_method) ? weight(:http_method) : nil
      end

      def tag_vote(entry)
        hit?(@tags, entry[:tags]) ? weight(:tag) : nil
      end

      def body_vote(entry)
        expected = entry[:request_body]
        return nil if expected.nil?

        expected == @body ? weight(:request_body) : nil
      end

      # Здесь что-то говорит только та операция, которая отказалась от
      # авторизации; операция с авторизацией оставляет этот сигнал
      # молчащим, а не голосует против.
      def unsecured_vote(entry)
        return nil if @secured

        entry[:unsecured] ? weight(:unsecured) : nil
      end

      def hit?(tokens, words)
        tokens.any? { |token| words.include?(token) }
      end

      def weight(signal)
        book.weight(signal).to_f
      end

      def cast_weight(votes)
        votes.values.flat_map(&:keys).uniq.sum { |signal| weight(signal) }
      end

      # Третий уровень доверия из CLAUDE.md: ниже порога или в плотной
      # борьбе роль всё равно присваивается лучшему кандидату — с настоящей
      # (низкой) уверенностью и предупреждением в отчёте. Пустое место тоже
      # ручной шаг, а эксперты 4 сентября 2026 просили, чтобы инструмент
      # решал сам. :unmapped остаётся только там, где кандидата нет вовсе:
      # ни один сигнал не совпал ни с одной ролью.
      def decide(votes, cast)
        ranked = rank(votes)
        role, score = ranked.first
        reason = rejection(score, ranked[1], cast)
        reason = :no_signal unless identified?(votes[role])
        return unmapped(ranked, cast, reason) if reason == :no_signal

        matched(role, ranked, Tally.new(vote: votes[role], score: score, cast: cast), reason)
      end

      def rank(votes)
        order = book.roles.each_with_index.to_h
        votes.map { |role, vote| [role, vote.values.sum] }
             .sort_by { |role, score| [-score, order[role]] }
      end

      # Порог `floor` проверяется раньше доли: когда голосуют только метод и
      # наличие тела, роль может взять 100% крошечного знаменателя, не зная
      # об эндпоинте ничего.
      # @return [Symbol, nil] почему роль присваивать нельзя
      def rejection(score, runner_up, cast)
        return :no_signal if score.nil? || score.zero? || cast.zero?
        return :below_threshold if score < book.scoring(:floor)
        return :below_threshold if (score / cast) < book.scoring(:minimum)
        return :ambiguous if lead(score, runner_up, cast) < book.scoring(:margin)

        nil
      end

      # Голос, который вообще ничего не говорит о роли: HTTP-метод и наличие
      # тела есть у половины эндпоинтов любой спецификации. Роль присваивается
      # только тому, за кого проголосовал хотя бы один опознающий сигнал —
      # имя операции, хвост пути, ресурс, тег или отказ от авторизации.
      def identified?(vote)
        vote && IDENTIFYING.any? { |signal| vote.key?(signal) }
      end

      def lead(score, runner_up, cast)
        (score - (runner_up ? runner_up.last : 0.0)) / cast
      end

      # Знаменатель уверенности — поданные голоса, но не меньше абсолютного
      # порога floor. Иначе операция, за которую проголосовали только метод и
      # наличие тела, взяла бы 100% крошечного знаменателя и отчиталась о
      # высокой уверенности, ничего о себе не зная.
      def denominator(cast)
        [cast, book.scoring(:floor).to_f].max
      end

      # Уверенность всегда настоящая — доля голосов победителя. Роль,
      # взятая ниже порога, отличается от уверенной не подкрученным числом,
      # а тем, что у неё есть reason: он поднимает предупреждение в отчёте.
      def matched(role, ranked, tally, reason)
        confidence = [tally.score / denominator(tally.cast), book.scoring(:ceiling)].min
        derived = IR::Derived.heuristic(role, confidence: confidence,
                                              evidence: evidence(ranked, tally, reason))
        Result.new(role: role, derived: derived, reason: reason, scores: ranked, cast: tally.cast)
      end

      # Роль, взятая ниже порога или в плотной борьбе, объясняется тем же
      # текстом, что и неприсвоенная: человеку важно увидеть, кто и с каким
      # отрывом победил, а не только имя роли.
      def evidence(ranked, tally, reason)
        return lost_evidence(ranked, tally.cast, reason) if reason

        won_evidence(tally.vote, tally.score, tally.cast, ranked)
      end

      # :unmapped — это решение, а не измерение, поэтому его уверенность
      # равна нулю, а набранные очки, приведшие к нему, идут в обоснование.
      def unmapped(ranked, cast, reason)
        evidence = lost_evidence(ranked, cast, reason)
        derived = IR::Derived.heuristic(:unmapped, confidence: 0.0, evidence: evidence)
        Result.new(role: :unmapped, derived: derived, reason: reason, scores: ranked, cast: cast)
      end

      def won_evidence(vote, score, cast, ranked)
        parts = Rules::OperationsBook::SIGNALS.filter_map do |signal|
          "#{signal} #{number(vote[signal])}" if vote.key?(signal)
        end
        Texts.t('analyzers.operation.match_evidence', parts: parts.join(', '),
                                                      score: number(score), cast: number(cast),
                                                      runner_up: runner_up_text(ranked))
      end

      def lost_evidence(ranked, cast, reason)
        return Texts.t('analyzers.operation.no_signal_evidence') if reason == :no_signal

        Texts.t('analyzers.operation.lost_evidence',
                reason: Texts.t("analyzers.operation.reason.#{reason}"),
                scores: scores_text(ranked), cast: number(cast),
                floor: number(book.scoring(:floor)), minimum: percent(:minimum),
                margin: percent(:margin))
      end

      def percent(key)
        format('%<share>d%%', share: book.scoring(key) * 100)
      end

      def runner_up_text(ranked)
        runner_up = ranked[1]
        return Texts.t('analyzers.operation.no_runner_up') if runner_up.nil? ||
                                                              runner_up.last.zero?

        Texts.t('analyzers.operation.runner_up', role: runner_up.first,
                                                 score: number(runner_up.last))
      end

      def scores_text(ranked)
        ranked.take(3).reject { |_, score| score.zero? }
              .map { |role, score| "#{role} #{number(score)}" }.join(', ')
      end

      def number(value)
        format('%.1f', value.to_f)
      end
    end
  end
end
