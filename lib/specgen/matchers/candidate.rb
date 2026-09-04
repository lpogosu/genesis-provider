# frozen_string_literal: true

module SpecGen
  module Matchers
    # Одна роль в ранжировании Composite вместе с тем, что за неё говорит.
    #
    #   role        одна из IR::Roles::FIELD
    #   points      сумма «вес матчера × балл голоса» по всем голосам
    #   total       сумма весов всех матчеров — знаменатель доли
    #   votes       голоса за роль, в порядке матчеров
    #   source      :registry, если имя — точное попадание в справочник,
    #               иначе :heuristic
    #   confidence  уверенность справочника для registry; доля очков,
    #               ограниченная потолком, для heuristic
    Candidate = Struct.new(:role, :points, :total, :votes, :source, :confidence, keyword_init: true)

    # Выборки Candidate.
    class Candidate
      # @return [Float] доля набранных очков от возможных
      def share
        total.zero? ? 0.0 : points / total
      end

      # @param matcher [Symbol]
      # @return [Vote, nil]
      def vote(matcher)
        votes.find { |vote| vote.matcher == matcher }
      end

      # @return [Boolean] роль опознана справочником имён
      def registry?
        source == :registry
      end

      # @return [Array<Vote>] голоса всех матчеров, кроме словарного
      def confirmations
        votes.reject(&:dictionary?)
      end
    end
  end
end
