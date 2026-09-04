# frozen_string_literal: true

module SpecGen
  module Matchers
    # Складывает голоса четырёх матчеров в ранжированный список кандидатов.
    #
    # Балл роли = Σ вес матчера × балл его голоса; уверенность = балл / сумма
    # всех весов, с потолком из справочника. Знаменатель фиксирован
    # намеренно: матчер, которому нечего сказать, снижает уверенность —
    # о поле без типа и без ограничений известно меньше, и цифра обязана
    # это показывать.
    #
    # Кандидатом становится только роль с опознающим голосом (имя; pattern,
    # example или enum из ограничений — Vote::IDENTIFYING); подтверждающие
    # голоса (расположение, тип, длина, числовые границы) добавляют очков
    # уже опознанным ролям и никого не выдвигают сами — иначе каждое
    # строковое поле под `recipient` получило бы пять кандидатов с равным
    # баллом. Одно исключение в другую сторону: слабый токен (`code`)
    # опознаёт роль только вместе с родителем — `error.code` кандидат,
    # `countryCode` нет. Точное попадание имени в справочник — источник
    # registry с уверенностью справочника: словарь точнее любой арифметики,
    # а подтверждения при нём лишь перечисляются в обосновании.
    #
    # Порядок детерминирован: по убыванию очков, при равенстве — по порядку
    # ролей в IR::Roles::FIELD.
    class Composite
      # Что насчитал матчер для одного поля.
      #
      #   candidates  Candidate, лучший первым; пусто, если никто не опознал
      #   total       сумма весов матчеров
      Result = Struct.new(:candidates, :total, keyword_init: true) do
        # @return [Candidate, nil]
        def best
          candidates.first
        end

        # @return [Candidate, nil]
        def runner_up
          candidates[1]
        end

        # @return [Boolean] ни один опознающий матчер не проголосовал
        def none?
          candidates.empty?
        end
      end

      # @param rules [Rules::Registry] все справочники: роли, статусы,
      #   валюты, заголовки подписи и идемпотентности
      def initialize(rules:)
        @book = rules.roles
        @matchers = {
          name: NameMatcher.new(book: @book, headers: header_dictionary(rules)),
          constraint: ConstraintMatcher.new(book: @book, statuses: rules.statuses,
                                            currencies: rules.currencies),
          structure: StructureMatcher.new(book: @book),
          type: TypeMatcher.new(book: @book)
        }.freeze
      end

      # @param subject [Subject]
      # @return [Result]
      def call(subject)
        votes = @matchers.to_h { |name, matcher| [name, matcher.call(subject)] }
        candidates = identified(votes).map { |role| candidate(role, votes) }
                                      .sort_by { |item| [-item.points, order(item.role)] }
        Result.new(candidates: candidates, total: @book.total_weight.to_f)
      end

      private

      # @return [Array<Symbol>] роли с опознающим голосом, в порядке IR
      def identified(votes)
        all = votes.values.flatten
        parents = votes[:structure].select { |vote| vote.kind == :parent }.map(&:role)
        roles = all.select(&:identifying?).map(&:role)
        roles += all.select { |vote| vote.weak_token? && parents.include?(vote.role) }.map(&:role)
        IR::Roles::FIELD & roles
      end

      def candidate(role, votes)
        own = Rules::RolesMatchers::MATCHERS.filter_map do |name|
          votes[name].find { |vote| vote.role == role }
        end
        points = own.sum { |vote| @book.weight(vote.matcher) * vote.score }
        registry = own.any?(&:dictionary?)
        Candidate.new(role: role, points: points, total: @book.total_weight.to_f, votes: own,
                      source: registry ? :registry : :heuristic,
                      confidence: confidence(points, registry))
      end

      def confidence(points, registry)
        return IR::Derived::REGISTRY_CONFIDENCE if registry

        [points / @book.total_weight, @book.scoring(:ceiling)].min
      end

      def order(role)
        IR::Roles::FIELD.index(role)
      end

      # Имена заголовков подписи и идемпотентности — те же словари, что
      # синонимы: Rules::Registry уже проверил, что они не заняты другой
      # ролью.
      # @return [Hash{String => Array(Symbol, String)}]
      def header_dictionary(rules)
        dictionary = {}
        Array(rules.signatures&.headers).each do |name|
          dictionary[name] = [:signature, Rules::SignaturesBook::FILE]
        end
        Array(rules.idempotency&.normalized).each do |name|
          dictionary[name] ||= [:idempotency_key, Rules::IdempotencyBook::FILE]
        end
        dictionary.freeze
      end
    end
  end
end
