# frozen_string_literal: true

module SpecGen
  module IR
    # Something the generator could not settle, or settled with doubt.
    # Warnings are a product, not a side effect: report.md is a paid
    # criterion, and `--fix` turns `suggested_overlay` into an overlay
    # skeleton the user fills in and feeds back through `--overlay`.
    #
    #   code               one of CODES, the machine-readable kind
    #   message            one sentence for a human
    #   json_path          the spec element to look at, in the same JSONPath
    #                      notation an Overlay uses for its targets, so a
    #                      warning and its fix address the same place
    #   severity           one of SEVERITIES
    #   suggested_overlay  YAML fragment that would resolve it, or nil
    Warning = Struct.new(:code, :message, :json_path, :severity, :suggested_overlay,
                         keyword_init: true)

    # Vocabulary, checks and ordering of Warning.
    class Warning
      include Node

      # Ordered by urgency; sorting and report sections rely on this order.
      SEVERITIES = %i[error warning info].freeze

      # Every kind of doubt the pipeline can produce. Grouped by stage:
      # loading and structure, operations, fields and schemas, amounts,
      # statuses and errors, webhooks, idempotency, auth, overlays.
      #
      # Two of the auth codes report what the spec plainly says rather than
      # what could not be derived: `auth_absent` (no security declared
      # anywhere) and `auth_key_in_query` (a credential the provider chose
      # to put in the query string, where proxy logs keep it). Both are
      # :info in the report, because a reader still has to see them.
      CODES = %i[
        spec_element_unsupported schema_unresolved example_missing
        provider_name_unknown server_environment_unknown
        operation_unmapped operation_id_missing operation_role_ambiguous
        undeclared_status_code
        field_role_unknown required_field_role_unknown conditional_required_hint
        format_unknown
        units_unknown units_inconsistent currency_unknown
        status_unmapped status_missing_from_enum
        error_code_undeclared error_code_unused error_action_unknown
        webhook_missing webhook_event_unmapped signature_profile_incomplete
        idempotency_header_missing idempotency_dedup_unclear
        auth_unknown auth_multiple_schemes auth_absent auth_key_in_query
        overlay_conflict overlay_target_missing
        contract_gap
      ].freeze

      # @param code [Symbol] one of CODES
      # @param message [String]
      # @param json_path [String, nil] JSONPath of the element in question
      # @param severity [Symbol] one of SEVERITIES
      # @param suggested_overlay [String, nil] YAML fragment that would fix it
      # @raise [ArgumentError] on an unknown code or severity
      def initialize(code:, message:, json_path: nil, severity: :warning, suggested_overlay: nil)
        Node.assert_member!(CODES, code, 'warning code')
        Node.assert_text!(message, 'warning message')
        Node.assert_member!(SEVERITIES, severity, 'warning severity')
        super
        freeze
      end

      # Deterministic order: urgency first, then location, then kind, so two
      # runs on the same spec produce byte-identical reports.
      # @return [Array]
      def sort_key
        [SEVERITIES.index(severity), json_path.to_s, code.to_s]
      end

      # @return [Boolean] generation cannot be considered complete
      def blocking?
        severity == :error
      end

      # @return [Boolean] a ready-made overlay fragment is available
      def fixable?
        !suggested_overlay.nil?
      end

      # @return [String] one line of report.md
      def to_s
        [severity.to_s.upcase, json_path, message].compact.join(' ')
      end
    end
  end
end
