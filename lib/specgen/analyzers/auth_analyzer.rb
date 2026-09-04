# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Fills IR::Auth: how the generated service authenticates its requests.
    #
    # This class picks *which* scheme to use and leaves the translation of
    # it to AuthScheme, which asks rules/auth.yml. Neither knows a scheme by
    # name: a provider that authenticates in a way we have not met yet is a
    # new entry in that dictionary, never a branch here.
    #
    # A spec may declare several schemes and use one. The choice is counted,
    # not guessed: how many operations require each scheme, ties broken by
    # declaration order, `security: []` (an inbound webhook) voting for
    # nothing. The schemes that lost are reported with their JSONPaths.
    #
    # Why a profile always gets an Auth, even when the spec declares none:
    # `auth: nil` cannot be told apart from "the analyzer never ran", while
    # `type: Derived.structural(:none)` says the spec was read and it really
    # asks for no credentials. Everything else - an unrecognised scheme, a
    # scheme required but never declared - is `Derived.unknown` with a
    # blocking warning, so a gap can never reach the generator disguised as
    # an open API.
    class AuthAnalyzer < Base
      # Fills `profile.auth`.
      # @return [IR::ProviderProfile] the profile it was given
      def call
        profile.auth = build_auth
        profile
      end

      private

      # @return [IR::Auth]
      def build_auth
        report_bad_security
        declared = declared_schemes
        report_undeclared(declared)
        chosen = requirements.winner(declared.keys)
        return no_declaration if chosen.nil?

        report_alternatives(declared, chosen)
        AuthScheme.call(name: chosen, declaration: declared[chosen], book: rules.auth,
                        profile: profile, asked_scopes: requirements.scopes_for(chosen))
      end

      # @return [SecurityRequirements]
      def requirements
        @requirements ||= SecurityRequirements.new(
          root: data['security'], root_path: json_path('security'),
          operations: operation_security
        )
      end

      # @return [Array<Array(Object, String)>] `security` of each operation
      def operation_security
        each_operation.map do |path, http_method, operation|
          [operation['security'], json_path('paths', path, http_method, 'security')]
        end
      end

      def report_bad_security
        requirements.bad_paths.each do |path|
          warn_shape(path, '`security` must be a list of requirement objects; it was ignored')
        end
      end

      # @return [Hash{String => Hash}] usable declarations, in spec order
      def declared_schemes
        components = data['components']
        schemes = components.is_a?(Hash) ? components['securitySchemes'] : nil
        return {} if schemes.nil?
        return warn_shape(schemes_path, '`securitySchemes` must be an object') || {} unless
          schemes.is_a?(Hash)

        schemes.select { |name, declaration| usable?(name, declaration) }
      end

      # @return [Boolean]
      def usable?(name, declaration)
        return true if declaration.is_a?(Hash)

        warn_shape(scheme_path(name), "security scheme #{name} must be an object; it was skipped")
        false
      end

      # A scheme an operation requires but `components` never defines. With
      # nothing else declared it blocks generation; alongside a scheme we do
      # recognise it is a contradiction worth reporting.
      def report_undeclared(declared)
        missing = requirements.names - declared.keys
        return if missing.empty?

        profile.warn(:auth_unknown,
                     "operations require security scheme #{missing.join(', ')}, which " \
                     'components.securitySchemes does not declare',
                     json_path: schemes_path, severity: declared.empty? ? :error : :warning)
      end

      def report_alternatives(declared, chosen)
        rejected = declared.keys - [chosen]
        return if rejected.empty?

        listed = rejected.map { |name| "#{name} (#{scheme_path(name)})" }.join(', ')
        profile.warn(:auth_multiple_schemes,
                     "the spec declares #{declared.size} security schemes; chose #{chosen}, " \
                     "required by #{requirements.counts[chosen]} operation(s); ignored #{listed}",
                     json_path: schemes_path)
      end

      # Nothing usable is declared: either the spec really asks for no
      # credentials, or it requires a scheme it never defines.
      # @return [IR::Auth]
      def no_declaration
        required = requirements.winner(requirements.names)
        return undeclared_auth(required) unless required.nil?

        profile.warn(:auth_absent,
                     'the spec declares no security at all, so generated requests carry no ' \
                     'credentials; unusual for a payment API, check it against the contract',
                     json_path: schemes_path, severity: :info)
        IR::Auth.new(type: IR::Derived.structural(
          :none, evidence: 'no components.securitySchemes, no operation declares security'
        ))
      end

      # @return [IR::Auth]
      def undeclared_auth(name)
        evidence = "#{name} is required by operations but declared nowhere"
        IR::Auth.new(scheme_name: name, json_path: scheme_path(name),
                     type: IR::Derived.unknown(evidence: evidence))
      end

      def schemes_path
        json_path('components', 'securitySchemes')
      end

      def scheme_path(name)
        json_path('components', 'securitySchemes', name)
      end

      def warn_shape(path, message)
        profile.warn(:spec_element_unsupported, message, json_path: path)
        nil
      end
    end
  end
end
