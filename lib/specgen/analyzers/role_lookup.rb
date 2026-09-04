# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Точный словарный поиск роли по имени поля — уровень 2 доверия, общий
    # для анализаторов, которым нужно найти поле суммы, валюты, статуса или
    # кода ошибки независимо от матчеров полей.
    #
    # Это тонкая точка входа, а не второй поиск: словарный шаг живёт в
    # Matchers::NameMatcher (#exact), тот же, с которого начинает композитный
    # матчер. Здесь только точное совпадение нормализованного имени с
    # синонимом из rules/roles.yml, без токенов, без Левенштейна и без
    # порогов. Найденное так поле анализатор использует для собственного
    # вывода (например, экспоненты валюты), но роль самому полю не
    # проставляет: роли полей в IR проставляют SchemaAnalyzer и
    # OperationAnalyzer через Matchers::Assigner, и два места, решающих одно
    # и то же, разошлись бы.
    #
    # Одно исключение сделано для кода ошибки. Голое `code` намеренно не
    # входит в синонимы роли error_code — так называют и код валюты, и код
    # банка. Поэтому код ошибки узнаётся структурно: токен имени из подсказок
    # `tokens` роли плюс родитель (свойство или схема), чьи токены совпадают
    # с подсказками `parents` — `error.code`, `PayoutError.code`. Проверки
    # те же, что у NameMatcher и StructureMatcher.
    class RoleLookup
      ERROR_CODE = :error_code

      # @param book [Rules::RolesBook]
      def initialize(book)
        @book = book
        @names = Matchers::NameMatcher.new(book: book)
      end

      # @param name [String, nil] имя поля или параметра как написано
      # @return [Symbol, nil] роль, синонимом которой является имя
      def role_of(name)
        @names.exact(name)
      end

      # @param name [String]
      # @param role [Symbol]
      # @return [Boolean] имя — точный синоним роли
      def role?(name, role)
        role_of(name) == role
      end

      # @param name [String] имя поля
      # @param role [Symbol] найденная роль
      # @return [String] обоснование для отчёта
      def evidence(name, role)
        Texts.t('analyzers.roles.synonym', name: name, role: role)
      end

      # Поле с кодом ошибки: точный синоним роли или токен `code` под
      # родителем-ошибкой.
      # @param name [String] имя поля
      # @param parents [Array<String>] имена родителей: свойство, схема
      # @return [Boolean]
      def error_code?(name, parents)
        return true if role?(name, ERROR_CODE)

        !error_parent(name, parents).nil?
      end

      # @param name [String]
      # @param parents [Array<String>]
      # @return [String] обоснование структурного распознавания кода ошибки
      def error_code_evidence(name, parents)
        return evidence(name, ERROR_CODE) if role?(name, ERROR_CODE)

        Texts.t('analyzers.roles.error_code_structure', name: name,
                                                        parent: error_parent(name, parents))
      end

      private

      # @return [String, nil] родитель-ошибка, если токен имени тоже совпал
      def error_parent(name, parents)
        return nil if @names.token(name, ERROR_CODE).nil?

        hit = Matchers::StructureMatcher.parent_hit(parents, @book.hints(ERROR_CODE)[:parents])
        hit&.first
      end
    end
  end
end
