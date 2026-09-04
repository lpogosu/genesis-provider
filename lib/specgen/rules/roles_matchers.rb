# frozen_string_literal: true

module SpecGen
  module Rules
    # Секция `matchers` rules/roles.yml: веса четырёх матчеров полей, пороги
    # решения и баллы отдельных сигналов.
    #
    # Подмешивается в RolesBook. Загрузчик строг по той же причине, что и у
    # ролей операций: нулевой вес молча выключил бы матчер, порог вне
    # [0, 1] сделал бы решение всегда «в отчёт» или никогда, а вес одного
    # матчера, дотягивающий до порога, позволил бы присвоить роль по
    # единственному сигналу — это догадка без пометки, которую доктрина трёх
    # уровней доверия запрещает.
    module RolesMatchers
      # Четыре матчера, в порядке строки обоснования.
      MATCHERS = %i[name constraint structure type].freeze
      # Числа, задающие решение целиком; все — доли.
      SCORING = %i[threshold margin ceiling].freeze
      # Баллы сигналов каждого матчера, доли от его веса, и их пороги.
      SCORES = {
        name: %i[token overlap min_overlap levenshtein min_similarity],
        constraint: %i[pattern example enum min_enum_share length bounds],
        structure: %i[parent location],
        type: %i[format compatible]
      }.freeze
      # Целочисленные настройки матчера: имя короче — Левенштейн не считается.
      INTEGERS = { name: %i[min_length] }.freeze
      # Списки слов матчера: токены, которые сами по себе роли не называют.
      LISTS = { name: %i[generic_tokens] }.freeze
      SECTIONS = (%w[weights scoring repeatable] + MATCHERS.map(&:to_s)).freeze
      FRACTION = (0.0..1.0)

      # @param matcher [Symbol] один из MATCHERS
      # @return [Integer] его вес; 0, пока книга не прошла проверку
      def weight(matcher)
        @weights.fetch(matcher, nil) || 0
      end

      # @return [Integer] сумма весов — знаменатель уверенности
      def total_weight
        MATCHERS.sum { |matcher| weight(matcher) }
      end

      # @param key [Symbol] один из SCORING
      # @return [Float]
      def scoring(key)
        @scoring.fetch(key, nil) || 0.0
      end

      # @param matcher [Symbol] один из MATCHERS
      # @param key [Symbol] сигнал или порог из SCORES / INTEGERS
      # @return [Numeric]
      def score(matcher, key)
        @scores.dig(matcher, key) || 0
      end

      # @param role [Symbol]
      # @return [Boolean] роль законно носят два поля одной схемы
      def repeatable?(role)
        @repeatable.include?(role)
      end

      # @return [Array<String>] нормализованные токены, общие для любых имён
      #   (`id`, `name`, `type`): один такой токен роли не называет
      def generic_tokens
        @scores.fetch(:name).fetch(:generic_tokens, [])
      end

      private

      def load_matchers
        section = matchers_section
        @weights = load_weights(section['weights'])
        @scoring = load_scoring(section['scoring'])
        @scores = MATCHERS.to_h { |matcher| [matcher, load_scores(section, matcher)] }.freeze
        @repeatable = load_repeatable(section['repeatable'])
        check_single_matcher
      end

      def matchers_section
        at = path('matchers')
        section = mapping(data['matchers'], noun(:matchers_section), at)
        report_unknown(section.keys.map(&:to_s) - SECTIONS, SECTIONS, at)
        section
      end

      def load_weights(value)
        at = path('matchers', 'weights')
        weights = mapping(value, noun(:matchers_weights), at)
        report_unknown(weights.keys.map(&:to_sym) - MATCHERS, MATCHERS, at)
        MATCHERS.to_h { |matcher| [matcher, weight_of(weights, matcher)] }.freeze
      end

      def weight_of(weights, matcher)
        at = path('matchers', 'weights', matcher)
        value = integer(weights[matcher.to_s], noun(:weight_of, signal: matcher), at)
        return value if value.nil? || value.positive?

        fault('operations.weight_zero', at, signal: matcher)
      end

      def load_scoring(value)
        at = path('matchers', 'scoring')
        scoring = mapping(value, noun(:matchers_scoring), at)
        report_unknown(scoring.keys.map(&:to_sym) - SCORING, SCORING, at)
        SCORING.to_h { |key| [key, fraction(scoring[key.to_s], "#{at}.#{key}", key)] }.freeze
      end

      def load_scores(section, matcher)
        at = path('matchers', matcher)
        scores = mapping(section[matcher.to_s], noun(:matcher_scores, matcher: matcher), at)
        report_unknown(scores.keys.map(&:to_sym) - allowed_keys(matcher), allowed_keys(matcher), at)
        [load_fractions(scores, matcher, at), load_integers(scores, matcher, at),
         load_lists(scores, matcher, at)].reduce(:merge).freeze
      end

      def allowed_keys(matcher)
        SCORES.fetch(matcher) + INTEGERS.fetch(matcher, []) + LISTS.fetch(matcher, [])
      end

      def load_lists(scores, matcher, at)
        LISTS.fetch(matcher, []).to_h do |key|
          listed = string_list(scores[key.to_s], noun(:list, key: key), "#{at}.#{key}",
                               required: false)
          [key, listed.map { |word| Normalizer.call(word) }.reject(&:empty?).uniq.freeze]
        end
      end

      def load_fractions(scores, matcher, at)
        SCORES.fetch(matcher).to_h { |key| [key, fraction(scores[key.to_s], "#{at}.#{key}", key)] }
      end

      def load_integers(scores, matcher, at)
        INTEGERS.fetch(matcher, []).to_h do |key|
          [key, integer(scores[key.to_s], noun(:matcher_setting, key: key), "#{at}.#{key}",
                        range: (1..))]
        end
      end

      def fraction(value, at, key)
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('matchers.fraction', at, key: key, range: FRACTION, got: describe(value))
        0.0
      end

      def load_repeatable(value)
        at = path('matchers', 'repeatable')
        return [].freeze if value.is_a?(Array) && value.empty?

        listed = string_list(value, noun(:list, key: 'repeatable'), at, required: false)
        listed.each_with_index.filter_map do |role, index|
          symbol_in(role, IR::Roles::FIELD, noun(:field_role), "#{at}[#{index}]")
        end.freeze
      end

      # Ни один матчер в одиночку не должен достигать порога: роль по одному
      # сигналу — догадка, а догадка обязана попасть в отчёт.
      def check_single_matcher
        total = total_weight
        return if total.zero?

        MATCHERS.each do |matcher|
          share = weight(matcher).to_f / total
          next if share < scoring(:threshold)

          fault('matchers.single_matcher', path('matchers', 'weights', matcher),
                matcher: matcher, share: format('%.2f', share),
                threshold: format('%.2f', scoring(:threshold)))
        end
      end

      def report_unknown(unknown, allowed, at)
        return if unknown.empty?

        fault('matchers.unknown_keys', at, keys: unknown.join(', '), allowed: allowed.join(', '))
      end
    end
  end
end
