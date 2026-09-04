# frozen_string_literal: true

module SpecGen
  module IR
    # How webhook signatures are verified. The default profile is Standard
    # Webhooks; anything else is :custom and each parameter has to be
    # derived separately, which a spec rarely states in full. Every
    # parameter is therefore a Derived that defaults to unknown, and
    # `missing` lists what the report has to ask for.
    #
    #   profile           Derived<Symbol> :standard_webhooks | :custom
    #   header            Derived<String> signature header name
    #   algorithm         Derived<Symbol> one of ALGORITHMS
    #   encoding          Derived<Symbol> :hex | :base64
    #   payload           Derived<Symbol> :raw_body | :id_timestamp_body
    #   tolerance         Derived<Integer> replay window in seconds; only
    #                     needed when payload includes a timestamp
    #   secret_key        Derived<String> key in provider.credentials
    #   id_header         delivery id header for :id_timestamp_body, or nil
    #   timestamp_header  timestamp header for :id_timestamp_body, or nil
    #   json_path         where the signature is documented
    SignatureProfile = Struct.new(:profile, :header, :algorithm, :encoding, :payload, :tolerance,
                                  :secret_key, :id_header, :timestamp_header, :json_path,
                                  keyword_init: true)

    # Vocabulary, defaults and completeness of SignatureProfile.
    class SignatureProfile
      include Node

      PROFILES = %i[standard_webhooks custom].freeze
      ALGORITHMS = %i[hmac_sha256 hmac_sha512 hmac_sha1].freeze
      ENCODINGS = %i[hex base64].freeze
      PAYLOADS = %i[raw_body id_timestamp_body].freeze
      # Members that must be known before a verifier can be generated.
      REQUIRED = %i[profile header algorithm encoding payload secret_key].freeze
      UNDERIVED = 'not derived'

      # @param profile [Derived]
      # @param header [Derived]
      # @param algorithm [Derived]
      # @param encoding [Derived]
      # @param payload [Derived]
      # @param tolerance [Derived]
      # @param secret_key [Derived]
      # @param id_header [String, nil]
      # @param timestamp_header [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(profile: Derived.unknown(evidence: UNDERIVED),
                     header: Derived.unknown(evidence: UNDERIVED),
                     algorithm: Derived.unknown(evidence: UNDERIVED),
                     encoding: Derived.unknown(evidence: UNDERIVED),
                     payload: Derived.unknown(evidence: UNDERIVED),
                     tolerance: Derived.unknown(evidence: UNDERIVED),
                     secret_key: Derived.unknown(evidence: UNDERIVED),
                     id_header: nil, timestamp_header: nil, json_path: nil)
        Node.assert_derived!(profile, 'signature profile', allowed: PROFILES)
        Node.assert_derived!(header, 'signature header')
        Node.assert_derived!(algorithm, 'signature algorithm', allowed: ALGORITHMS)
        Node.assert_derived!(encoding, 'signature encoding', allowed: ENCODINGS)
        Node.assert_derived!(payload, 'signature payload', allowed: PAYLOADS)
        Node.assert_derived!(tolerance, 'signature tolerance')
        Node.assert_derived!(secret_key, 'signature secret key')
        super
      end

      # @return [Array<Symbol>] members still unknown, in member order
      def missing
        needed = REQUIRED.dup
        needed << :tolerance if payload.value == :id_timestamp_body
        needed.reject { |member| self[member].known? }
      end

      # @return [Boolean] a verifier can be generated without TODOs
      def complete?
        missing.empty?
      end

      # @return [Boolean]
      def standard?
        profile.value == :standard_webhooks
      end
    end
  end
end
