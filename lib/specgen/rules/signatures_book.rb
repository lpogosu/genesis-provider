# frozen_string_literal: true

module SpecGen
  module Rules
    # Named webhook signature profiles. A provider references a profile
    # instead of restating the HMAC parameters, and the default profile is
    # the open Standard Webhooks specification.
    #
    # The two payload shapes have opposite requirements, and the dictionary
    # is checked both ways: `id_timestamp_body` needs the id header, the
    # timestamp header and a replay tolerance, while `raw_body` must not
    # carry them - a tolerance on a payload with no timestamp in it would
    # read as replay protection that does not exist.
    class SignaturesBook < Book
      FILE = 'signatures.yml'
      # CLAUDE.md makes Standard Webhooks the default, so it must be present.
      DEFAULT_PROFILE = 'standard_webhooks'
      TIMESTAMPED = %i[id_header timestamp_header tolerance].freeze
      TOLERANCE_RANGE = (1..86_400)
      VOCABULARY = {
        'profile' => [IR::SignatureProfile::PROFILES, 'signature profile'],
        'algorithm' => [IR::SignatureProfile::ALGORITHMS, 'signature algorithm'],
        'encoding' => [IR::SignatureProfile::ENCODINGS, 'signature encoding'],
        'payload' => [IR::SignatureProfile::PAYLOADS, 'signature payload']
      }.freeze

      # @return [Array<String>] normalized names of headers that carry a
      #   signature, taken from `header_names` and from the profiles
      attr_reader :headers

      # @param name [String] profile name
      # @return [Hash, nil] profile with symbol keys
      def profile(name)
        @profiles[name.to_s]
      end

      # @return [Hash, nil] the Standard Webhooks profile
      def default
        @profiles[DEFAULT_PROFILE]
      end

      # @return [Array<String>] profile names, in dictionary order
      def names
        @profiles.keys
      end

      # @param header [String] header name seen in a spec
      # @return [Boolean]
      def signature_header?(header)
        @headers.include?(Normalizer.call(header))
      end

      private

      def build
        @profiles = {}
        section('profiles').each { |name, body| add(name, body) }
        check_default
        @headers = collect_headers
        [@profiles, @headers].each(&:freeze)
      end

      def check_default
        return if default

        complain("profile #{DEFAULT_PROFILE} is required as the default", path('profiles'))
      end

      def add(name, body)
        at = path('profiles', name)
        fields = mapping(body, "profile #{name}", at)
        entry = vocabularies(fields, at)
        entry[:header] = text(fields['header'], 'signature header', "#{at}.header")
        entry[:secret_key] = text(fields['secret_key'], 'secret key name', "#{at}.secret_key")
        entry[:value_prefix] = fields['value_prefix']
        entry[:source] = fields['source']
        check_replay(entry, fields, at)
        @profiles[name.to_s] = entry.freeze
      end

      def vocabularies(fields, at)
        VOCABULARY.to_h do |key, (allowed, what)|
          [key.to_sym, symbol_in(fields[key], allowed, what, "#{at}.#{key}")]
        end
      end

      def check_replay(entry, fields, at)
        TIMESTAMPED.each { |key| entry[key] = fields[key.to_s] }
        return check_timestamped(entry, at) if entry[:payload] == :id_timestamp_body

        present = TIMESTAMPED.select { |key| entry[key] }
        return if present.empty?

        complain("#{present.join(', ')} only apply to an id_timestamp_body payload; a raw body " \
                 'carries no timestamp to bound', at)
      end

      def check_timestamped(entry, at)
        entry[:id_header] = text(entry[:id_header], 'delivery id header', "#{at}.id_header")
        entry[:timestamp_header] = text(entry[:timestamp_header], 'timestamp header',
                                        "#{at}.timestamp_header")
        entry[:tolerance] = integer(entry[:tolerance], 'replay tolerance', "#{at}.tolerance",
                                    range: TOLERANCE_RANGE)
      end

      def collect_headers
        declared = string_list(data['header_names'], 'header names', path('header_names'))
        from_profiles = @profiles.values.filter_map { |entry| entry[:header] }
        (declared + from_profiles).map { |header| Normalizer.call(header) }
                                  .reject(&:empty?).uniq.sort
      end
    end
  end
end
