# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Fills IR::Info and IR::Server: who the provider is, which OpenAPI
    # dialect describes it, and which of its hosts is the sandbox.
    #
    # Nothing here is stated formally in a spec. `info.title` is marketing
    # prose and `servers[].description` is a free-text label, so every value
    # is either taken from the command line (certain) or read out of words
    # (heuristic, carrying the evidence report.md prints).
    #
    # The provider name is the one thing that may never be invented
    # silently: it decides the class name, the file name and the ENV
    # variable the base URL comes from. When neither --provider nor the
    # title yields anything, the profile gets an unknown and a blocking
    # warning instead of a plausible guess.
    class InfoAnalyzer < Base
      # Words that describe an API rather than name a provider. Industry
      # vocabulary, not provider names: nothing here belongs to one company,
      # and a title made only of these words derives nothing.
      COMMON_WORDS = %w[
        api apis rest restful http https openapi swagger spec specification
        service services integration integrations gateway platform
        payment payments payout payouts payin payins deposit deposits refund refunds
        open public partner merchant provider
        sandbox staging production docs documentation reference mock demo test version
      ].freeze

      # "v1", "v2.1": a version tag in a title, never a name.
      VERSION_WORD = /\Av\d+(\.\d+)*\z/
      # Word boundary for slugs. ASCII only: the slug becomes a Ruby
      # constant and a file name.
      NON_SLUG = /[^a-z0-9]+/
      # Everything a POSIX environment variable name may not contain.
      NON_ENV = /[^A-Z0-9]/
      ENV_SUFFIX = '_BASE_URL'

      # One word left after the common vocabulary is dropped reads as a
      # brand name; several words mean the title said more than the name.
      SINGLE_WORD_CONFIDENCE = 0.8
      MULTI_WORD_CONFIDENCE = 0.6

      SERVERS_OVERLAY = <<~YAML
        - target: "$"
          update:
            servers:
              - url: https://api.example.com
                description: Production
      YAML

      # Fills `profile.info` and `profile.servers`.
      # @return [IR::ProviderProfile] the profile it was given
      def call
        profile.info = build_info
        profile.servers.concat(build_servers)
        profile
      end

      private

      # @return [IR::Info]
      def build_info
        name = provider_name
        IR::Info.new(name: name, title: info_text('title'), spec_version: info_text('version'),
                     oas_version: document.version, oas_family: document.family,
                     base_url_env: base_url_env(name), spec_file: spec_file)
      end

      # --provider wins over prose: a human who names the provider is never
      # second-guessed by a title.
      # @return [IR::Derived]
      def provider_name
        name_from_option || name_from_title || unknown_name
      end

      # @return [IR::Derived, nil]
      def name_from_option
        given = option(:provider)
        slug = slugify(given)
        return nil if slug.empty?

        IR::Derived.structural(slug, evidence: "--provider #{given}")
      end

      # @return [IR::Derived, nil]
      def name_from_title
        title = info_text('title')
        words = title.nil? ? [] : meaningful_words(title)
        return nil if words.empty?

        slug = words.join('_')
        evidence = "info.title #{title.inspect} -> #{slug}"
        IR::Derived.heuristic(slug, confidence: title_confidence(words), evidence: evidence)
      end

      # @return [IR::Derived]
      def unknown_name
        profile.warn(:provider_name_unknown,
                     'provider name could not be derived: pass --provider to name the ' \
                     'service class, its file and its ENV variables',
                     json_path: json_path('info', 'title'), severity: :error)
        IR::Derived.unknown(evidence: 'neither --provider nor info.title yielded a name')
      end

      # The generated service reads its base URL from ENV, never from a
      # literal, so the profile carries the variable name. It is exactly as
      # certain as the provider name it is built from, and no more.
      # @param name [IR::Derived] provider name
      # @return [IR::Derived]
      def base_url_env(name)
        return IR::Derived.unknown(evidence: 'no provider name to build an ENV name from') if
          name.unknown?

        variable = name.value.upcase.gsub(NON_ENV, '_') + ENV_SUFFIX
        evidence = "convention: <PROVIDER>#{ENV_SUFFIX} from provider name #{name.value.inspect}"
        IR::Derived.new(value: variable, source: name.source, confidence: name.confidence,
                        evidence: evidence)
      end

      # @return [Array<IR::Server>] one per usable entry, in spec order
      def build_servers
        entries = data['servers']
        return no_servers(entries) unless entries.is_a?(Array) && !entries.empty?

        entries.each_with_index.filter_map { |entry, index| build_server(entry, index) }
      end

      # @return [Array] empty, so the caller reads one code path
      def no_servers(entries)
        said = entries.nil? ? 'declares no `servers`' : 'has an empty or malformed `servers` list'
        profile.warn(:spec_element_unsupported,
                     "the spec #{said}; the generated service has no base URL to default to",
                     json_path: json_path('servers'), suggested_overlay: SERVERS_OVERLAY)
        []
      end

      # @return [IR::Server, nil] nil for an entry without a usable url
      def build_server(entry, index)
        path = json_path('servers', index)
        url = entry.is_a?(Hash) ? entry['url'] : nil
        return skipped_server(path) unless url.is_a?(String) && !url.strip.empty?

        description = scalar(entry['description'])
        IR::Server.new(url: url, environment: environment(url, description, path),
                       description: description, json_path: path)
      end

      # @return [nil]
      def skipped_server(path)
        profile.warn(:spec_element_unsupported,
                     'server entry carries no usable `url` string and was skipped',
                     json_path: path)
        nil
      end

      # @return [IR::Derived] the environment, or unknown with a warning
      def environment(url, description, path)
        EnvironmentDetector.call(url: url, description: description) ||
          unknown_environment(path)
      end

      # @return [IR::Derived] unknown, with the warning already recorded
      def unknown_environment(path)
        profile.warn(:server_environment_unknown,
                     'neither the description nor the host says whether this server is the ' \
                     'sandbox or production; requests may go to the wrong one',
                     json_path: path, severity: :info,
                     suggested_overlay: environment_overlay(path))
        IR::Derived.unknown(evidence: 'no environment word in description or host')
      end

      # @return [String] overlay action that names the environment by hand
      def environment_overlay(path)
        "- target: \"#{path}\"\n  update:\n    description: Production\n"
      end

      # Reduces a name to the identifier the generated class and file are
      # named after. Unlike Rules::Normalizer, camel case is deliberately
      # *not* split: a brand written as one word stays one word, so a title
      # like "AcmePay" gives "acmepay" and not "acme_pay".
      # @return [String] empty when nothing usable is left
      def slugify(text)
        words_of(text).join('_')
      end

      # @return [Array<String>] title words that could name a provider
      def meaningful_words(title)
        words_of(title).reject do |word|
          COMMON_WORDS.include?(word) || word.match?(VERSION_WORD)
        end
      end

      # @return [Float]
      def title_confidence(words)
        words.one? ? SINGLE_WORD_CONFIDENCE : MULTI_WORD_CONFIDENCE
      end

      # @return [Array<String>] lower-case ASCII words
      def words_of(text)
        text.to_s.downcase.split(NON_SLUG).reject(&:empty?)
      end

      # @return [String, nil] basename, the form reports show
      def spec_file
        file = document.file
        file.nil? ? nil : File.basename(file.to_s)
      end

      # @return [String, nil] value of an `info` key, nil when absent or not scalar
      def info_text(key)
        section = data['info']
        scalar(section.is_a?(Hash) ? section[key] : nil)
      end

      # @return [String, nil] scalars verbatim, structures ignored
      def scalar(value)
        return nil unless value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)

        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
