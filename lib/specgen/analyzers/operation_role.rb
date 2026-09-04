# frozen_string_literal: true

module SpecGen
  module Analyzers
    # What an endpoint is for, decided by counting votes.
    #
    # No spec states the role of an operation, and no single signal settles
    # it: `POST /payouts` could be a payout or a webhook receiver, and
    # `payoutWebhook` names both. So each signal - operationId, the tail of
    # the path, the resource words in it, the HTTP method, the tag, the
    # presence of a body, the absence of security - votes with the weight
    # rules/operations.yml gives it, and the role with the most votes wins.
    # This is the composite matcher of COMA (Rahm & Bernstein 2001) applied
    # to endpoints instead of columns: several independent matchers, weights,
    # aggregation, threshold.
    #
    # Confidence is arithmetic, not a feeling: the winner's share of the
    # weight of every signal that voted at all. A signal that could not vote
    # - no operationId in the spec - stays out of the denominator, because
    # missing input is reported as its own warning and must not quietly
    # deflate a decision made on everything else.
    #
    # Below the threshold, or too close to the runner-up, the answer is
    # :unmapped with the scores kept for the report. Guessing here would put
    # a cancel endpoint into `create_request`.
    class OperationRole
      # What the matcher decided, and everything the report needs to explain it.
      #
      #   role        the winning role, or :unmapped
      #   derived     IR::Derived carrying role, confidence and evidence
      #   reason      nil when a role won, else :no_signal, :below_threshold
      #               or :ambiguous
      #   scores      [[role, score]] best first
      #   cast        total weight of the signals that voted
      Result = Struct.new(:role, :derived, :reason, :scores, :cast, keyword_init: true)

      TEMPLATE = /\A\{.+\}\z/

      # @param book [Rules::OperationsBook] words, weights and thresholds
      # @param id [String, nil] operationId
      # @param http_method [Symbol]
      # @param path [String] path template
      # @param tags [Array<String>]
      # @param body [Boolean] the operation declares a requestBody
      # @param secured [Boolean] false when it declares `security: []`
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

      # @return [Hash{Symbol => Float}] signal => weight it gave this role
      def votes_for(role)
        entry = book.entry(role)
        { operation_id: id_vote(entry), path_tail: tail_vote(entry),
          path_resource: resource_vote(entry), http_method: method_vote(entry),
          tag: tag_vote(entry), request_body: body_vote(entry),
          unsecured: unsecured_vote(entry) }.compact
      end

      # A verb and a noun together name the role; one of the two alone is a
      # hint worth a fraction of the weight.
      def id_vote(entry)
        return nil if @id_tokens.empty?

        verb = hit?(@id_tokens, entry[:verbs])
        noun = hit?(@id_tokens, entry[:nouns]) || hit?(@id_tokens, entry[:resources])
        return weight(:operation_id) if verb && noun
        return weight(:operation_id) * book.scoring(:partial) if verb || noun

        nil
      end

      # A path ending in a template parameter reads a resource; a path
      # ending in a word is that word.
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

      # Only an operation that opts out of security says anything here; a
      # secured one leaves this signal silent instead of voting against.
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

      def decide(votes, cast)
        order = book.roles.each_with_index.to_h
        ranked = votes.map { |role, vote| [role, vote.values.sum] }
                      .sort_by { |role, score| [-score, order[role]] }
        role, score = ranked.first
        reason = rejection(score, ranked[1], cast)
        return unmapped(ranked, cast, reason) unless reason.nil?

        matched(role, votes[role], score, cast, ranked)
      end

      # The floor is checked before the share: with only a method and a body
      # voting, a role can take 100% of a tiny denominator while knowing
      # nothing about the endpoint.
      # @return [Symbol, nil] why no role may be assigned
      def rejection(score, runner_up, cast)
        return :no_signal if score.nil? || score.zero? || cast.zero?
        return :below_threshold if score < book.scoring(:floor)
        return :below_threshold if (score / cast) < book.scoring(:minimum)
        return :ambiguous if lead(score, runner_up, cast) < book.scoring(:margin)

        nil
      end

      def lead(score, runner_up, cast)
        (score - (runner_up ? runner_up.last : 0.0)) / cast
      end

      def matched(role, vote, score, cast, ranked)
        confidence = [score / cast, book.scoring(:ceiling)].min
        evidence = won_evidence(vote, score, cast, ranked)
        derived = IR::Derived.heuristic(role, confidence: confidence, evidence: evidence)
        Result.new(role: role, derived: derived, reason: nil, scores: ranked, cast: cast)
      end

      # :unmapped is a decision, not a measurement, so its confidence is
      # zero and the scores that led to it go into the evidence.
      def unmapped(ranked, cast, reason)
        evidence = lost_evidence(ranked, cast, reason)
        derived = IR::Derived.heuristic(:unmapped, confidence: 0.0, evidence: evidence)
        Result.new(role: :unmapped, derived: derived, reason: reason, scores: ranked, cast: cast)
      end

      def won_evidence(vote, score, cast, ranked)
        parts = Rules::OperationsBook::SIGNALS.filter_map do |signal|
          "#{signal} #{number(vote[signal])}" if vote.key?(signal)
        end
        "composite match: #{parts.join(', ')} = #{number(score)} of #{number(cast)} " \
          "votes cast; #{runner_up_text(ranked)}"
      end

      def lost_evidence(ranked, cast, reason)
        return 'no signal matched any role' if reason == :no_signal

        "#{reason}: #{scores_text(ranked)} of #{number(cast)} votes cast " \
          "(floor #{number(book.scoring(:floor))}, minimum #{percent(:minimum)}, " \
          "margin #{percent(:margin)})"
      end

      def percent(key)
        format('%<share>d%%', share: book.scoring(key) * 100)
      end

      def runner_up_text(ranked)
        runner_up = ranked[1]
        return 'nothing else scored' if runner_up.nil? || runner_up.last.zero?

        "next #{runner_up.first} #{number(runner_up.last)}"
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
