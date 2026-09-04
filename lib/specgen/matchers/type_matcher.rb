# frozen_string_literal: true

module SpecGen
  module Matchers
    # Роль по `type` и `format` — подтверждающий матчер.
    #
    # Тип сам по себе роли не называет: строкой объявлены почти все поля, а
    # `format: date-time` носят и created_at, и completed_at. Поэтому голос
    # типа учитывается только за роли, которые уже опознал матчер имени или
    # ограничений (Composite), и лишь добавляет уверенности. Формат — тот же
    # голос с другим обоснованием: он точнее, чем тип, но и его одного мало.
    class TypeMatcher
      MATCHER = :type

      # @param book [Rules::RolesBook]
      def initialize(book:)
        @book = book
      end

      # @param subject [Subject]
      # @return [Array<Vote>] в порядке ролей IR; пусто у поля без типа
      def call(subject)
        return [] if subject.type.nil? && subject.format.nil?

        @book.roles.filter_map { |role| vote_for(subject, role) }
      end

      private

      def vote_for(subject, role)
        hints = @book.hints(role)
        if subject.format && hints[:formats].include?(subject.format)
          return vote(role, :format, t('format', format: subject.format))
        end
        return nil unless subject.type && hints[:types].include?(subject.type.to_s.to_sym)

        vote(role, :compatible, t('compatible', type: subject.type))
      end

      def vote(role, kind, evidence)
        Vote.new(matcher: MATCHER, role: role, score: @book.score(MATCHER, kind), kind: kind,
                 evidence: evidence)
      end

      def t(key, **params)
        Texts.t("matchers.type.#{key}", **params)
      end
    end
  end
end
