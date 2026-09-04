# frozen_string_literal: true

module SpecGen
  module Matchers
    # Один голос одного матчера за одну роль.
    #
    #   matcher   :name | :constraint | :structure | :type
    #   role      одна из IR::Roles::FIELD
    #   score     0.0..1.0, доля от веса матчера
    #   kind      какой сигнал сработал: :synonym, :token, :pattern, :parent…
    #   evidence  фраза для отчёта, что именно совпало
    Vote = Struct.new(:matcher, :role, :score, :kind, :evidence, keyword_init: true)

    # Проверки Vote.
    class Vote
      RANGE = (0.0..1.0)
      # Сигналы имени, которые означают точное попадание в справочник: роль
      # с таким голосом получает источник registry, а не heuristic.
      DICTIONARY = %i[synonym header].freeze
      # Сигналы, которые опознают роль сами; остальные (тип, родитель,
      # расположение, длина, числовые границы) только подтверждают уже
      # опознанную: без них `page` с `minimum: 1` стал бы кандидатом в сумму.
      # Слабый токен (`code`, kind :weak_token) опознаёт роль только вместе с
      # родителем — это решает Composite.
      IDENTIFYING = { name: %i[synonym header token overlap levenshtein],
                      constraint: %i[pattern_same pattern_sample example enum] }.freeze
      WEAK_TOKEN = :weak_token

      # @param matcher [Symbol]
      # @param role [Symbol]
      # @param score [Numeric]
      # @param kind [Symbol]
      # @param evidence [String]
      # @raise [ArgumentError] при роли вне словаря или балле вне [0, 1]
      def initialize(matcher:, role:, score:, kind:, evidence:)
        IR::Roles.field!(role)
        unless score.is_a?(Numeric) && RANGE.cover?(score)
          raise ArgumentError, "балл голоса: ожидается число в #{RANGE}, получено #{score.inspect}"
        end

        super(matcher: matcher, role: role, score: score.to_f, kind: kind, evidence: evidence)
        freeze
      end

      # @return [Boolean] голос — точное попадание в справочник имён
      def dictionary?
        matcher == :name && DICTIONARY.include?(kind)
      end

      # @return [Boolean] голос выдвигает роль в кандидаты, а не подтверждает
      def identifying?
        IDENTIFYING.fetch(matcher, []).include?(kind)
      end

      # @return [Boolean] токен, который опознаёт роль только с родителем
      def weak_token?
        matcher == :name && kind == WEAK_TOKEN
      end
    end
  end
end
