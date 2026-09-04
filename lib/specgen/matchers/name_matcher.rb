# frozen_string_literal: true

module SpecGen
  module Matchers
    # Роль по имени поля: словарь → токены → расстояние Левенштейна.
    #
    # Словарь первым и отдельно, потому что строковые метрики не связывают
    # семантически разные имена: `sum` и `amount` не похожи ни одной буквой,
    # и только строка синонима в rules/roles.yml делает их одной ролью
    # (классический пример из литературы по schema matching — Ship и
    # Deliver). Точное совпадение с синонимом — уровень справочника: один
    # голос, других имя не получает. Тем же словарём считаются имена
    # заголовков подписи и идемпотентности из rules/signatures.yml и
    # rules/idempotency.yml — реестр справочников уже проверил, что они не
    # заняты другой ролью.
    #
    # Без словарного попадания голосуют слабые сигналы, для каждой роли —
    # лучший из трёх: токен из подсказок `tokens` (`amt`, `code`, `msg`),
    # доля общих токенов с ближайшим синонимом (`recipient_phone_number` ~
    # `recipient_phone`) и сходство по Левенштейну с ним (`amout` ~ `amount`).
    # Их баллы заданы так, что одного имени для порога не хватает: опечатка
    # или частичное совпадение — кандидат, а не решение.
    #
    # Это же и точка входа Analyzers::RoleLookup: #exact — тот самый
    # словарный поиск, которым остальные анализаторы находят поле суммы или
    # статуса до и независимо от матчеров.
    class NameMatcher
      MATCHER = :name

      # @param book [Rules::RolesBook]
      # @param headers [Hash{String => Array(Symbol, String)}] нормализованное
      #   имя заголовка => роль и файл справочника, из которого оно известно
      def initialize(book:, headers: {})
        @book = book
        @headers = headers
      end

      # Точный синоним из rules/roles.yml.
      # @param name [String, nil] имя как написано
      # @return [Symbol, nil]
      def exact(name)
        return nil if name.nil?

        @book.role_for(name)
      end

      # Токен имени, совпавший с подсказками `tokens` роли.
      # @param name [String]
      # @param role [Symbol]
      # @return [String, nil]
      def token(name, role)
        (Rules::Normalizer.tokens(name) & @book.hints(role)[:tokens]).first
      end

      # @param subject [Subject]
      # @return [Array<Vote>] в порядке ролей IR
      def call(subject)
        dictionary(subject) || @book.roles.filter_map { |role| weakest_best(subject, role) }
      end

      private

      def dictionary(subject)
        role = exact(subject.name)
        return [vote(role, 1.0, :synonym, t('synonym', name: subject.name, role: role))] if role

        role, file = @headers[subject.normalized]
        return nil if role.nil?

        [vote(role, 1.0, :header, t('header', name: subject.name, file: file))]
      end

      # Лучший из слабых сигналов; при равенстве — первый, порядок
      # фиксирован.
      def weakest_best(subject, role)
        [token_vote(subject, role), overlap_vote(subject, role), levenshtein_vote(subject, role)]
          .compact.max_by(&:score)
      end

      # Токен из generic_tokens (`code`) — слабый: он опознаёт роль только
      # вместе с родителем (`error.code`), о чём знает Composite.
      def token_vote(subject, role)
        hit = token(subject.name, role)
        return nil if hit.nil?

        kind = @book.generic_tokens.include?(hit) ? :weak_token : :token
        vote(role, score(:token), kind, t('token', token: hit, role: role))
      end

      # Общий токен обязан что-то значить: `debug_id` и `id` делят только
      # `id`, а это слово встречается в любом идентификаторе (generic_tokens
      # в rules/roles.yml).
      def overlap_vote(subject, role)
        synonym, share = closest_synonym(subject.tokens.uniq, role)
        return nil if synonym.nil? || share < score(:min_overlap)

        common = subject.tokens & synonym.split('_')
        return nil if (common - @book.generic_tokens).empty?

        vote(role, score(:overlap) * share, :overlap,
             t('overlap', synonym: synonym, tokens: common.join(', '), share: percent(share)))
      end

      # @return [Array(String, Float), nil] синоним с наибольшей долей общих
      #   токенов (Жаккар) и сама доля
      def closest_synonym(tokens, role)
        return nil if tokens.empty?

        @book.names(role).map { |name| [name, jaccard(tokens, name.split('_'))] }.max_by(&:last)
      end

      def jaccard(left, right)
        union = left | right
        union.empty? ? 0.0 : (left & right).size.fdiv(union.size)
      end

      def levenshtein_vote(subject, role)
        name = subject.normalized
        return nil if name.size < score(:min_length)

        synonym, similarity = @book.names(role)
                                   .map { |known| [known, Levenshtein.similarity(name, known)] }
                                   .max_by(&:last)
        return nil if synonym.nil? || similarity < score(:min_similarity)

        vote(role, score(:levenshtein) * similarity, :levenshtein,
             t('levenshtein', name: name, synonym: synonym, similarity: format('%.2f', similarity)))
      end

      def vote(role, points, kind, evidence)
        Vote.new(matcher: MATCHER, role: role, score: points, kind: kind, evidence: evidence)
      end

      def score(key)
        @book.score(MATCHER, key)
      end

      def percent(share)
        format('%<share>d%%', share: (share * 100).round)
      end

      def t(key, **params)
        Texts.t("matchers.name.#{key}", **params)
      end
    end
  end
end
