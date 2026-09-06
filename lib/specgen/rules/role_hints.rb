# frozen_string_literal: true

module SpecGen
  module Rules
    # Слабые подсказки записи роли в rules/roles.yml — всё, кроме `names`.
    #
    # Подмешивается в RolesBook. Подсказки взвешивают матчеры, поэтому
    # между ролями они пересекаются свободно; загрузчик проверяет только
    # форму и одно содержательное противоречие: образец значения (`samples`),
    # который не подходит ни под один `patterns` той же роли, — ошибка
    # данных, иначе ConstraintMatcher принимал бы за шаблон роли то, что
    # роль сама не принимает.
    module RoleHints
      # Типы данных OpenAPI, с которыми может быть объявлено поле роли.
      TYPES = %i[array boolean integer number object string].freeze
      # Списки строк записи роли, кроме `names`: как ключ YAML => ключ IR.
      LISTS = { 'tokens' => :tokens, 'formats' => :formats, 'parents' => :parents,
                'avoid_parents' => :avoid_parents, 'samples' => :samples,
                'enum_values' => :enum_values }.freeze
      # Подсказки, которые хранятся нормализованными, как токены имени.
      NORMALIZED = %i[tokens parents avoid_parents enum_values].freeze
      NO_HINTS = { names: [], tokens: [], types: [], formats: [], patterns: [], parents: [],
                   avoid_parents: [], locations: [], samples: [], enum_values: [], lengths: [],
                   bounds: false }.freeze

      private

      # @param fields [Hash] запись роли без `names`
      # @param at [String] JSONPath записи
      # @return [Hash] подсказки под ключами NO_HINTS, кроме :names
      def compile_hints(fields, at)
        hints = LISTS.to_h { |key, name| [name, hint_list(fields, key, name, at)] }
        hints[:types] = types_of(fields['types'], "#{at}.types")
        hints[:patterns] = patterns_of(fields['patterns'], "#{at}.patterns")
        hints[:locations] = locations_of(fields['locations'], "#{at}.locations")
        hints[:lengths] = lengths_of(fields['lengths'], "#{at}.lengths")
        hints[:bounds] = fields['bounds'] == true
        check_samples(hints, at)
        check_parents(hints, at)
        hints
      end

      def hint_list(fields, key, name, at)
        listed = string_list(fields[key], noun(:list, key: key), "#{at}.#{key}", required: false)
        return listed.uniq unless NORMALIZED.include?(name)

        listed.map { |value| Normalizer.call(value) }.reject(&:empty?).uniq
      end

      def types_of(value, at)
        listed = string_list(value, noun(:list, key: 'types'), at, required: false)
        listed.each_with_index.filter_map do |type, index|
          symbol_in(type, TYPES, noun(:openapi_type), "#{at}[#{index}]")
        end
      end

      def patterns_of(value, at)
        sources = string_list(value, noun(:list, key: 'patterns'), at, required: false)
        sources.each_with_index.filter_map do |source, index|
          pattern(source, noun(:pattern), "#{at}[#{index}]")
        end
      end

      def locations_of(value, at)
        listed = string_list(value, noun(:list, key: 'locations'), at, required: false)
        listed.each_with_index.filter_map do |place, index|
          symbol_in(place, IR::Parameter::LOCATIONS, noun(:parameter_location), "#{at}[#{index}]")
        end
      end

      def lengths_of(value, at)
        return [] if value.nil?

        unless value.is_a?(Array) && !value.empty?
          fault('checks.list', at, what: noun(:list, key: 'lengths'), got: describe(value))
          return []
        end
        value.each_with_index.filter_map do |length, index|
          integer(length, noun(:length), "#{at}[#{index}]", range: (1..))
        end
      end

      # Слово, которое роль одновременно ждёт и запрещает у родителя, —
      # противоречие: подсказка `parents` и запрет `avoid_parents` погасили
      # бы друг друга, и никто бы этого не заметил.
      def check_parents(hints, at)
        both = hints[:parents] & hints[:avoid_parents]
        return if both.empty?

        fault('roles.parents_conflict', "#{at}.avoid_parents", words: both.join(', '))
      end

      # Образец, который не подходит под шаблоны своей роли, — противоречие.
      def check_samples(hints, at)
        return if hints[:samples].empty? || hints[:patterns].empty?

        hints[:samples].each_with_index do |sample, index|
          next if hints[:patterns].any? { |regexp| regexp.match?(sample) }

          fault('roles.sample_mismatch', "#{at}.samples[#{index}]", sample: sample.inspect)
        end
      end
    end
  end
end
