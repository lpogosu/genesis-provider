# frozen_string_literal: true

module SpecGen
  module Rules
    # Provider status strings → the internal statuses of IR::Roles.
    #
    # `canonical` is the mapping the case description fixes and the experts
    # confirmed, `synonyms` extends it with the words other providers use,
    # and `ambiguous` lists strings that mean different things at different
    # providers and must never be mapped quietly — those become a warning
    # and a question in report.md instead. A status belongs to exactly one
    # of the three: mapped twice, it stops the load.
    class StatusesBook < Book
      FILE = 'statuses.yml'

      # @return [Hash{String => Symbol}] every mapped status, normalized
      attr_reader :index

      # @param status [String] status value from a spec or a response
      # @return [Symbol, nil] internal status; nil when unknown or ambiguous
      def internal_for(status)
        @index[Normalizer.call(status)]
      end

      # @param status [String]
      # @return [Boolean] the word means different things at different providers
      def ambiguous?(status)
        @ambiguous.key?(Normalizer.call(status))
      end

      # @param status [String]
      # @return [String, nil] why it is ambiguous, for report.md
      def ambiguity(status)
        @ambiguous[Normalizer.call(status)]
      end

      # @param status [String]
      # @return [Boolean] the mapping comes from the case description itself
      def canonical?(status)
        @canonical.include?(Normalizer.call(status))
      end

      private

      def build
        @index = {}
        @origins = {}
        @canonical = []
        @ambiguous = {}
        load_canonical
        load_synonyms
        load_ambiguous
        report_uncovered
        [@index, @origins, @canonical, @ambiguous].each(&:freeze)
      end

      def load_canonical
        section('canonical').each do |status, internal|
          at = path('canonical', status)
          target = symbol_in(internal, IR::Roles::INTERNAL_STATUS, 'internal status', at)
          next if target.nil?

          key = map_status(status, target, at)
          @canonical << key if key
        end
      end

      def load_synonyms
        section('synonyms').each do |internal, statuses|
          at = path('synonyms', internal)
          target = symbol_in(internal, IR::Roles::INTERNAL_STATUS, 'internal status', at)
          next if target.nil?

          string_list(statuses, "synonyms of #{internal}", at).each_with_index do |status, index|
            map_status(status, target, "#{at}[#{index}]")
          end
        end
      end

      def load_ambiguous
        section('ambiguous', Hash, required: false).each do |status, reason|
          at = path('ambiguous', status)
          note = text(reason, "reason #{status} is ambiguous", at)
          key = Normalizer.call(status)
          next if note.nil? || mapped_already?(key, at)

          @ambiguous[key] = note
        end
      end

      def map_status(status, internal, at)
        key = Normalizer.call(status)
        if key.empty?
          complain("status #{status.inspect} normalizes to an empty name", at)
          return nil
        end
        return nil if mapped_already?(key, at)

        @index[key] = internal
        @origins[key] = at
        key
      end

      def mapped_already?(key, at)
        owner = @index[key]
        return false if owner.nil?

        complain("status #{key.inspect} is already mapped to #{owner} at #{@origins[key]}; " \
                 'one status means one internal state', at)
        true
      end

      def report_uncovered
        missing = IR::Roles::INTERNAL_STATUS - @index.values.uniq
        return if missing.empty?

        complain("no provider status maps to #{missing.join(', ')}", path('synonyms'))
      end
    end
  end
end
