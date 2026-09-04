# frozen_string_literal: true

module SpecGen
  module Rules
    # Имена полей так, как их пишут провайдеры, → роли IR::Roles::FIELD.
    #
    # `names` — синонимы: точное совпадение после нормализации, и ни одно
    # имя не может принадлежать двум ролям. Столкновение останавливает
    # загрузку с указанием обеих ролей, потому что молча оставить первое
    # совпадение — это ровно тот путь, которым синоним одной роли попадает в
    # поле другой роли в сгенерированном платёжном запросе. Остальные
    # подсказки — `tokens`, `types`, `formats`, `patterns`, `parents` — не
    # принимаются на веру, а взвешиваются матчерами, поэтому им можно
    # пересекаться свободно.
    class RolesBook < Book
      FILE = 'roles.yml'
      # Типы данных OpenAPI, с которыми может быть объявлено поле роли.
      TYPES = %i[array boolean integer number object string].freeze
      NO_HINTS = { names: [], tokens: [], types: [], formats: [], patterns: [],
                   parents: [] }.freeze

      # @param name [String] имя поля, как написано в спецификации
      # @return [Symbol, nil] роль поля; nil, если синоним не совпал
      def role_for(name)
        @names[Normalizer.call(name)]
      end

      # @return [Array<Symbol>] роли, описанные справочником, в порядке IR
      def roles
        IR::Roles::FIELD & @entries.keys
      end

      # @param role [Symbol]
      # @return [Hash] :names, :tokens, :types, :formats, :patterns, :parents
      def hints(role)
        @entries.fetch(role, NO_HINTS)
      end

      # @param role [Symbol]
      # @return [Array<String>] нормализованные синонимы роли
      def names(role)
        hints(role)[:names]
      end

      # @return [Hash{String => Symbol}] все синонимы, нормализованные
      def index
        @names
      end

      private

      def build
        @entries = {}
        @names = {}
        @origins = {}
        section('roles').each { |key, body| add(key, body) }
        report_missing
        [@entries, @names, @origins].each(&:freeze)
      end

      def add(key, body)
        at = path('roles', key)
        role = symbol_in(key, IR::Roles::FIELD, noun(:field_role), at)
        return if role.nil?

        @entries[role] = compile(role, mapping(body, noun(:role_body, role: key), at), at)
      end

      def compile(role, hints, at)
        {
          names: claim_all(role, list(hints, 'names', at, required: true), "#{at}.names"),
          tokens: normalized(list(hints, 'tokens', at)),
          types: types_of(hints['types'], "#{at}.types"),
          formats: list(hints, 'formats', at),
          patterns: patterns_of(hints['patterns'], "#{at}.patterns"),
          parents: normalized(list(hints, 'parents', at))
        }.freeze
      end

      def list(hints, key, at, required: false)
        string_list(hints[key], noun(:list, key: key), "#{at}.#{key}", required: required)
      end

      def normalized(values)
        values.map { |value| Normalizer.call(value) }.reject(&:empty?).uniq
      end

      def claim_all(role, values, at)
        values.each_with_index.filter_map do |value, index|
          claim(role, value, "#{at}[#{index}]")
        end.uniq
      end

      def claim(role, value, at)
        name = Normalizer.call(value)
        if name.empty?
          fault('roles.empty_synonym', at, name: value.inspect)
          return nil
        end
        owner = @names[name]
        return conflict(name, owner, at) if owner && owner != role

        @names[name] = role
        @origins[name] = at
        name
      end

      def conflict(name, owner, at)
        fault('roles.conflict', at, name: name.inspect, owner: owner, origin: @origins[name])
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

      def report_missing
        missing = IR::Roles::FIELD - @entries.keys
        return if missing.empty?

        fault('roles.missing', path('roles'), roles: missing.join(', '))
      end
    end
  end
end
