# frozen_string_literal: true

module SpecGen
  module Matchers
    # Превращает кандидата Composite в IR::Derived с обоснованием и решает,
    # нужно ли о нём сообщать.
    #
    # Порог решает не «присваивать ли роль», а «попадёт ли решение в отчёт»
    # (эксперты на чекпоинте 1: инструмент должен решать больше сам). Роль
    # получает лучший кандидат всегда; ниже порога или при слишком малом
    # отрыве от второго кандидата решение помечается сомнительным, и Assigner
    # пишет предупреждение с баллами всех кандидатов — они уйдут в report.md
    # и в TODO сгенерированного кода.
    #
    # Обоснование — арифметика, которую можно проверить: каждый голос с
    # весом и тем, что именно совпало, сумма, знаменатель и следующий
    # кандидат. У роли из справочника имён впереди стоит сам синоним, а
    # голоса остальных матчеров перечислены как подтверждения.
    class Decision
      # @param book [Rules::RolesBook] пороги и веса
      def initialize(book:)
        @book = book
      end

      # @param candidate [Candidate] выбранный кандидат
      # @param result [Composite::Result] всё ранжирование, ради соседа
      # @param prefix [String, nil] фраза перед обоснованием: почему выбран
      #   не первый кандидат
      # @return [IR::Derived] registry для точного синонима, иначе heuristic
      def derive(candidate, result, prefix: nil)
        evidence = [prefix, evidence_for(candidate, result)].compact.join
        return IR::Derived.registry(candidate.role, evidence: evidence) if candidate.registry?

        IR::Derived.heuristic(candidate.role, confidence: candidate.confidence, evidence: evidence)
      end

      # Отрыв считается по уверенности, а не по очкам: роль из справочника
      # уверена по определению, и оспорить её может overlay или правка
      # справочника, а не близкий по очкам эвристический сосед — он остаётся
      # в обосновании как «следующая».
      # @param candidate [Candidate]
      # @param result [Composite::Result]
      # @return [Symbol, nil] :low — ниже порога, :ambiguous — следующий
      #   кандидат слишком близко, nil — сомнений нет
      def doubt(candidate, result)
        return :low if candidate.confidence < threshold

        follower = following(candidate, result)
        return nil if follower.nil?

        (candidate.confidence - follower.confidence) < @book.scoring(:margin) ? :ambiguous : nil
      end

      # @return [Float] порог отчёта
      def threshold
        @book.scoring(:threshold)
      end

      # @param result [Composite::Result]
      # @param limit [Integer]
      # @return [String] "amount 0.46, currency 0.15"
      def candidates_text(result, limit = 4)
        result.candidates.take(limit)
              .map { |candidate| "#{candidate.role} #{number(candidate.confidence)}" }.join(', ')
      end

      private

      def following(candidate, result)
        index = result.candidates.index { |other| other.equal?(candidate) }
        index.nil? ? nil : result.candidates[index + 1]
      end

      def evidence_for(candidate, result)
        runner_up = runner_up_text(candidate, result)
        return heuristic_evidence(candidate, result, runner_up) unless candidate.registry?

        parts = candidate.confirmations.map { |vote| part(vote) }
        t('registry', hit: candidate.vote(:name).evidence, runner_up: runner_up,
                      parts: parts.empty? ? t('no_confirmations') : parts.join(', '))
      end

      def heuristic_evidence(candidate, result, runner_up)
        t('composite', parts: candidate.votes.map { |vote| part(vote) }.join(', '),
                       score: number(candidate.points, 1), total: number(result.total, 1),
                       runner_up: runner_up)
      end

      def part(vote)
        points = @book.weight(vote.matcher) * vote.score
        t('part', matcher: vote.matcher, points: number(points, 1), detail: vote.evidence)
      end

      def runner_up_text(candidate, result)
        follower = following(candidate, result)
        return t('no_runner_up') if follower.nil?

        t('runner_up', role: follower.role, score: number(follower.share))
      end

      def number(value, digits = 2)
        format("%.#{digits}f", value.to_f)
      end

      def t(key, **params)
        Texts.t("matchers.evidence.#{key}", **params)
      end
    end
  end
end
