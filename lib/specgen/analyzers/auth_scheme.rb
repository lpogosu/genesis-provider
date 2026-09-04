# frozen_string_literal: true

module SpecGen
  module Analyzers
    # One declared security scheme, translated into IR::Auth.
    #
    # The translation carries no knowledge of any scheme: the declaration
    # goes to rules/auth.yml through AuthBook, and what comes back - type,
    # location, credential keys, the parameter that carries the credential -
    # is copied into the IR with the dictionary entry named as evidence.
    # Everything the dictionary does not cover (an unknown scheme, an OAuth2
    # flow without a tokenUrl, an apiKey with no name) becomes a warning
    # instead of an invented value.
    class AuthScheme
      # What a human would write to make an unknown scheme recognisable,
      # as an OpenAPI Overlay action.
      UNKNOWN_OVERLAY = "- target: %{path}\n  update:\n    " \
                        "# restate the scheme in terms rules/auth.yml knows,\n    " \
                        "# or add an entry to that dictionary\n    " \
                        "type: http\n    scheme: bearer\n"

      # @param kwargs [Hash] see #initialize
      # @return [IR::Auth]
      def self.call(**)
        new(**).call
      end

      # @param name [String] key under components.securitySchemes
      # @param declaration [Hash] the security scheme as the spec wrote it
      # @param book [Rules::AuthBook] the dictionary that recognises schemes
      # @param profile [IR::ProviderProfile] receives the warnings
      # @param asked_scopes [Array<String>] scopes operations asked for
      def initialize(name:, declaration:, book:, profile:, asked_scopes: [])
        @name = name
        @declaration = declaration
        @book = book
        @profile = profile
        @asked_scopes = asked_scopes
        @path = SpecLoader::JsonPath.build(['components', 'securitySchemes', name])
      end

      # @return [IR::Auth] with an unknown type when the dictionary has no
      #   entry for this scheme
      def call
        entry, flow = match
        return unknown if entry.nil?

        build(entry, flow)
      end

      private

      attr_reader :name, :declaration, :book, :profile, :path

      # Lets the dictionary decide which OAuth2 flow it supports: every
      # declared flow is offered in spec order and the first one an entry
      # matches wins.
      # @return [Array(Hash, String), Array(nil, nil)] entry and flow name
      def match
        flows = declaration['flows']
        return [book.scheme_for(declaration), nil] unless flows.is_a?(Hash)

        flows.each_key do |flow|
          entry = book.scheme_for(declaration, flow: flow)
          return [entry, flow] unless entry.nil?
        end
        [nil, nil]
      end

      # @return [IR::Auth]
      def build(entry, flow)
        param_name = book.param_name_for(entry, declaration)
        note_query_risk(entry)
        missing_param_name if param_name.nil? && book.spec_names_param?(entry)
        IR::Auth.new(scheme_name: name, type: type_of(entry), location: entry[:location],
                     param_name: param_name, credential_keys: credential_keys(entry),
                     token_url: token_url(entry, flow), scopes: scopes,
                     json_path: path)
      end

      # @return [IR::Derived] the type, naming both the dictionary entry and
      #   the facts of the spec that selected it
      def type_of(entry)
        facts = entry[:match].map { |key, value| "#{key}=#{value}" }.join(', ')
        IR::Derived.registry(entry[:ir_type],
                             evidence: "rules/auth.yml entry #{entry_name(entry)} " \
                                       "matched #{facts}")
      end

      # @return [IR::Derived]
      def credential_keys(entry)
        keys = entry[:credential_keys]
        IR::Derived.registry(keys,
                             evidence: "rules/auth.yml entry #{entry_name(entry)} reads " \
                                       "provider.credentials #{keys.join(', ')}")
      end

      # @return [String, nil] token endpoint, when the entry needs one
      def token_url(entry, flow)
        return nil unless entry[:token_url_required]

        url = flow_body(flow)['tokenUrl']
        return url if url.is_a?(String) && !url.strip.empty?

        warn(:auth_unknown, "the #{flow} flow declares no tokenUrl, so the generated " \
                            'service has nowhere to ask for a token',
             at: "#{path}.flows#{SpecLoader::JsonPath.segment(flow)}", severity: :error)
        nil
      end

      # Scopes the scheme declares in its flows plus those the operations
      # asked for, sorted, so two runs generate the same code.
      # @return [Array<String>]
      def scopes
        (declared_scopes | @asked_scopes).sort
      end

      # @return [Array<String>]
      def declared_scopes
        flows = declaration['flows']
        return [] unless flows.is_a?(Hash)

        flows.each_value.flat_map { |body| scopes_of(body) }
      end

      # @return [Array<String>]
      def scopes_of(body)
        scopes = body.is_a?(Hash) ? body['scopes'] : nil
        scopes.is_a?(Hash) ? scopes.keys.map(&:to_s) : []
      end

      # @return [Hash] the flow object, empty when the spec has none
      def flow_body(flow)
        flows = declaration['flows']
        body = flows.is_a?(Hash) ? flows[flow] : nil
        body.is_a?(Hash) ? body : {}
      end

      # rules/auth.yml documents the risk of a credential in the query
      # string; the report repeats it, because the provider chose it.
      def note_query_risk(entry)
        return unless entry[:location] == :query

        warn(:auth_key_in_query,
             'the credential travels in the query string, where proxy logs and browser ' \
             'history keep it; the provider chose this, not the generator', severity: :info)
      end

      def missing_param_name
        warn(:auth_unknown,
             "security scheme #{name} names no parameter, so there is nothing to put the " \
             'credential in', severity: :error)
      end

      # @return [IR::Auth]
      def unknown
        overlay = format(UNKNOWN_OVERLAY, path: path.inspect)
        warn(:auth_unknown,
             "security scheme #{name} matches no entry in rules/auth.yml, so the generated " \
             'service cannot authenticate',
             severity: :error, overlay: overlay)
        IR::Auth.new(scheme_name: name, json_path: path,
                     type: IR::Derived.unknown(evidence: "#{name} matches no dictionary entry"))
      end

      def entry_name(entry)
        book.name_of(entry).inspect
      end

      def warn(code, message, at: path, severity: :warning, overlay: nil)
        profile.warn(code, message, json_path: at, severity: severity, suggested_overlay: overlay)
      end
    end
  end
end
