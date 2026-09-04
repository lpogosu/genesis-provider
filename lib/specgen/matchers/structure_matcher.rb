# frozen_string_literal: true

module SpecGen
  module Matchers
    # Роль по месту поля в схеме: имя родителя и расположение параметра.
    # Подтверждающий матчер.
    #
    # `recipient.phone`, `error.code`, `PayoutError.message` — родитель
    # называет область, в которой имя поля читается однозначно, и именно он
    # отличает код ошибки от кода валюты. Но один родитель не называет роль:
    # под `recipient` лежат пять ролей. Поэтому голос родителя, как и голос
    # расположения (заголовок для подписи и ключа идемпотентности, путь для
    # идентификатора операции), Composite учитывает только за роли, которые
    # уже опознали имя или ограничения.
    #
    # Родитель сравнивается по токенам, а не строкой: подсказка `error`
    # обязана сработать и на свойстве `error`, и на схеме `PayoutError`.
    class StructureMatcher
      MATCHER = :structure

      # Родитель, чьи токены пересекаются со словами подсказки. Общая
      # проверка для матчера и для Analyzers::RoleLookup, узнающего код
      # ошибки структурно.
      # @param parents [Array<String>] имена родителей
      # @param words [Array<String>] нормализованные подсказки `parents` роли
      # @return [Array(String, String), nil] родитель и совпавший токен
      def self.parent_hit(parents, words)
        Array(parents).each do |parent|
          token = (Rules::Normalizer.tokens(parent) & words).first
          return [parent, token] if token
        end
        nil
      end

      # @param book [Rules::RolesBook]
      def initialize(book:)
        @book = book
      end

      # @param subject [Subject]
      # @return [Array<Vote>] в порядке ролей IR
      def call(subject)
        @book.roles.filter_map do |role|
          [parent_vote(subject, role), location_vote(subject, role)].compact.max_by(&:score)
        end
      end

      private

      def parent_vote(subject, role)
        parent, token = self.class.parent_hit(subject.parents, @book.hints(role)[:parents])
        return nil if parent.nil?

        vote(role, :parent, t('parent', parent: parent, token: token))
      end

      def location_vote(subject, role)
        return nil unless @book.hints(role)[:locations].include?(subject.location)

        vote(role, :location, t('location', location: Texts.t("location.#{subject.location}")))
      end

      def vote(role, kind, evidence)
        Vote.new(matcher: MATCHER, role: role, score: @book.score(MATCHER, kind), kind: kind,
                 evidence: evidence)
      end

      def t(key, **params)
        Texts.t("matchers.structure.#{key}", **params)
      end
    end
  end
end
