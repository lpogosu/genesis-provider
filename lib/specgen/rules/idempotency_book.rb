# frozen_string_literal: true

module SpecGen
  module Rules
    # The Idempotency-Key header: the names the industry gives it, and how
    # the generated service produces a value.
    #
    # The key is derived from `operation.id` with UUID v5 and a fixed
    # namespace, so a retry produces the same key and the provider returns
    # the earlier result instead of paying twice. That is also why nothing
    # here may be random: the namespace is a constant in the dictionary, and
    # a namespace that is not a UUID stops the load.
    class IdempotencyBook < Book
      FILE = 'idempotency.yml'
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      STATUS_RANGE = (100..599)

      # @return [String, nil] the name the generated service sends
      attr_reader :canonical_header
      # @return [Array<String>] header names as written in the dictionary
      attr_reader :aliases
      # @return [Array<String>] the same names, normalized for lookup
      attr_reader :normalized
      # @return [Symbol, nil] one of IR::Idempotency::STRATEGIES
      attr_reader :default_strategy
      # @return [String, nil] fixed UUID v5 namespace
      attr_reader :namespace
      # @return [Integer, nil] status the provider answers a repeat with
      attr_reader :conflict_status

      # @param header [String] header name seen in a spec
      # @return [Boolean] the header is a known idempotency key
      def alias?(header)
        @normalized.include?(Normalizer.call(header))
      end

      # @return [Boolean] send the key even where the spec marks it optional
      def send_when_optional?
        @send_when_optional
      end

      private

      def build
        @canonical_header = text(data['canonical_header'], 'canonical header',
                                 path('canonical_header'))
        @aliases = string_list(data['aliases'], 'aliases', path('aliases'))
        @normalized = collect_aliases.freeze
        load_strategy
      end

      def load_strategy
        @default_strategy = symbol_in(data['default_strategy'], IR::Idempotency::STRATEGIES,
                                      'idempotency strategy', path('default_strategy'))
        @conflict_status = integer(data['conflict_status'], 'conflict status',
                                   path('conflict_status'), range: STATUS_RANGE)
        @send_when_optional = data.fetch('send_when_optional', true) == true
        @namespace = uuid_namespace
      end

      def uuid_namespace
        at = path('uuid_v5_namespace')
        value = text(data['uuid_v5_namespace'], 'UUID v5 namespace', at)
        return nil if value.nil?
        return value if value.match?(UUID)

        complain("UUID v5 namespace must be a UUID, got #{value.inspect}", at)
        nil
      end

      def collect_aliases
        seen = {}
        @aliases.each_with_index do |name, index|
          record(seen, name, "#{path('aliases')}[#{index}]")
        end
        check_canonical(seen)
        seen.keys
      end

      def record(seen, name, at)
        key = Normalizer.call(name)
        return complain("alias #{name.inspect} normalizes to an empty name", at) if key.empty?
        return complain("alias #{name.inspect} repeats #{seen[key].inspect}", at) if seen.key?(key)

        seen[key] = name
      end

      def check_canonical(seen)
        return if @canonical_header.nil?
        return if seen.key?(Normalizer.call(@canonical_header))

        complain("canonical header #{@canonical_header.inspect} is missing from the aliases",
                 path('aliases'))
      end
    end
  end
end
