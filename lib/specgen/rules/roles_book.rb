# frozen_string_literal: true

module SpecGen
  module Rules
    # Field names as providers spell them → the roles of IR::Roles::FIELD.
    #
    # `names` are synonyms: an exact match after normalization, and no name
    # may belong to two roles. A collision stops the load with both roles
    # named, because silently keeping the first match is how a synonym of one
    # role ends up filling another role's field in a generated payment
    # request. The other hints — `tokens`, `types`, `formats`, `patterns`,
    # `parents` — are weighed by the matchers rather than trusted outright,
    # so they may overlap freely.
    class RolesBook < Book
      FILE = 'roles.yml'
      # OpenAPI data types a field carrying the role may be declared with.
      TYPES = %i[array boolean integer number object string].freeze
      NO_HINTS = { names: [], tokens: [], types: [], formats: [], patterns: [],
                   parents: [] }.freeze

      # @param name [String] field name as written in a spec
      # @return [Symbol, nil] field role, nil when no synonym matches
      def role_for(name)
        @names[Normalizer.call(name)]
      end

      # @return [Array<Symbol>] roles the dictionary defines, in IR order
      def roles
        IR::Roles::FIELD & @entries.keys
      end

      # @param role [Symbol]
      # @return [Hash] :names, :tokens, :types, :formats, :patterns, :parents
      def hints(role)
        @entries.fetch(role, NO_HINTS)
      end

      # @param role [Symbol]
      # @return [Array<String>] normalized synonyms of the role
      def names(role)
        hints(role)[:names]
      end

      # @return [Hash{String => Symbol}] every synonym, normalized
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
        role = symbol_in(key, IR::Roles::FIELD, 'field role', at)
        return if role.nil?

        @entries[role] = compile(role, mapping(body, "role #{key}", at), at)
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
        string_list(hints[key], key, "#{at}.#{key}", required: required)
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
          complain("synonym #{value.inspect} normalizes to an empty name", at)
          return nil
        end
        owner = @names[name]
        return conflict(name, owner, at) if owner && owner != role

        @names[name] = role
        @origins[name] = at
        name
      end

      def conflict(name, owner, at)
        complain("synonym #{name.inspect} is already claimed by role #{owner} " \
                 "at #{@origins[name]}; a name may mean one thing only", at)
        nil
      end

      def types_of(value, at)
        string_list(value, 'types', at, required: false).each_with_index.filter_map do |type, index|
          symbol_in(type, TYPES, 'OpenAPI type', "#{at}[#{index}]")
        end
      end

      def patterns_of(value, at)
        sources = string_list(value, 'patterns', at, required: false)
        sources.each_with_index.filter_map do |source, index|
          pattern(source, 'pattern', "#{at}[#{index}]")
        end
      end

      def report_missing
        missing = IR::Roles::FIELD - @entries.keys
        return if missing.empty?

        complain("no synonyms for #{missing.join(', ')}; every role of IR::Roles::FIELD needs " \
                 'an entry', path('roles'))
      end
    end
  end
end
