# frozen_string_literal: true

module SpecGen
  module Matchers
    # Роль по ограничениям JSON Schema: `pattern`, `example`, `enum`,
    # `maxLength`, числовые границы. Опознающий матчер: `pattern: ^7\d{10}$`
    # называет телефон, как бы поле ни звали.
    #
    # Шаблон из спецификации не сравнивается с шаблонами роли текстом —
    # одно и то же пишут десятью способами. Вместо этого он проверяется
    # образцами значений ролей (`samples` в rules/roles.yml): шаблон,
    # принимающий образец телефона, — шаблон телефона. Шаблон, принимающий
    # образцы нескольких ролей (`^\d+$`), не говорит ничего и не голосует.
    # Так же `example` проверяется шаблонами ролей. Значения enum читаются
    # справочниками статусов и валют ISO 4217 и подсказками `enum_values`:
    # голос равен доле значений, которые прочитались.
    class ConstraintMatcher
      MATCHER = :constraint
      NUMERIC = %w[integer number].freeze
      BOUNDS = %i[minimum maximum exclusive_minimum exclusive_maximum].freeze
      # Шаблон из чужой спецификации выполняется с ограничением по времени:
      # катастрофический откат не имеет права повесить генератор.
      TIMEOUT = 0.05

      # @param book [Rules::RolesBook]
      # @param statuses [Rules::StatusesBook]
      # @param currencies [Rules::CurrenciesBook]
      def initialize(book:, statuses:, currencies:)
        @book = book
        @statuses = statuses
        @currencies = currencies
      end

      # @param subject [Subject]
      # @return [Array<Vote>] не больше одного голоса на роль, в порядке ролей IR
      def call(subject)
        constraints = subject.constraints || {}
        votes = pattern_votes(constraints[:pattern]) + example_votes(subject.example) +
                enum_votes(constraints) + length_votes(constraints[:max_length]) +
                bounds_votes(subject, constraints)
        @book.roles.filter_map { |role| votes.select { |vote| vote.role == role }.max_by(&:score) }
      end

      private

      def pattern_votes(source)
        return [] unless source.is_a?(String)

        regexp = compile(source)
        hits = @book.roles.filter_map { |role| pattern_hit(role, source, regexp) }
        hits = hits.select { |_, kind, _| kind == :pattern_same } if hits.size > 1
        hits.map { |role, kind, sample| vote(role, :pattern, kind, t(kind, sample: sample)) }
      end

      # @return [Array(Symbol, Symbol, String), nil] роль, вид совпадения и
      #   принятый образец
      def pattern_hit(role, source, regexp)
        hints = @book.hints(role)
        return [role, :pattern_same, source] if hints[:patterns].any? { |own| own.source == source }
        return nil if regexp.nil?

        sample = hints[:samples].find { |candidate| safe_match?(regexp, candidate) }
        [role, :pattern_sample, sample] if sample
      end

      def compile(source)
        Regexp.new(source, timeout: TIMEOUT)
      rescue RegexpError, TypeError
        nil
      end

      def safe_match?(regexp, value)
        regexp.match?(value)
      rescue Regexp::TimeoutError
        false
      end

      def example_votes(example)
        return [] unless example.is_a?(String)

        hits = @book.roles.select do |role|
          @book.hints(role)[:patterns].any? { |own| safe_match?(own, example) }
        end
        return [] unless hits.size == 1

        [vote(hits.first, :example, :example, t('example', example: example[0, 40]))]
      end

      def enum_votes(constraints)
        values = constraints.key?(:const) ? [constraints[:const]] : constraints[:enum]
        strings = values.is_a?(Array) ? values.grep(String) : []
        return [] if strings.empty?

        [status_vote(strings), currency_vote(strings), *hinted_votes(strings)].compact
      end

      def status_vote(strings)
        share_vote(:status, strings, 'enum_status') { |value| @statuses.internal_for(value) }
      end

      def currency_vote(strings)
        share_vote(:currency, strings, 'enum_currency') do |value|
          @currencies.known?(value.strip.upcase)
        end
      end

      def hinted_votes(strings)
        @book.roles.filter_map do |role|
          known = @book.hints(role)[:enum_values]
          next if known.empty?

          share_vote(role, strings, 'enum_values') { |value| known.include?(normalize(value)) }
        end
      end

      def share_vote(role, strings, key, &)
        share = strings.count(&).fdiv(strings.size)
        return nil if share < score(:min_enum_share)

        Vote.new(matcher: MATCHER, role: role, score: score(:enum) * share, kind: :enum,
                 evidence: t(key, share: "#{(share * 100).round}%"))
      end

      def length_votes(max_length)
        return [] unless max_length.is_a?(Integer)

        @book.roles.select { |role| @book.hints(role)[:lengths].include?(max_length) }
             .map { |role| vote(role, :length, :length, t('length', length: max_length)) }
      end

      def bounds_votes(subject, constraints)
        present = BOUNDS.select { |key| constraints.key?(key) }
        return [] if present.empty? || !(subject.type.nil? || NUMERIC.include?(subject.type))

        @book.roles.select { |role| @book.hints(role)[:bounds] }
             .map { |role| vote(role, :bounds, :bounds, t('bounds', keywords: present.join(', '))) }
      end

      def vote(role, score_key, kind, evidence)
        Vote.new(matcher: MATCHER, role: role, score: score(score_key), kind: kind,
                 evidence: evidence)
      end

      def normalize(value)
        Rules::Normalizer.call(value)
      end

      def score(key)
        @book.score(MATCHER, key)
      end

      def t(key, **params)
        Texts.t("matchers.constraint.#{key}", **params)
      end
    end
  end
end
