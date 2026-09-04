# frozen_string_literal: true

module SpecGen
  module IR
    # Identity of the provider and of the document it was derived from.
    #
    #   name          Derived<String> provider slug used for class and file
    #                 names, e.g. "acmepay" (from --provider or info.title)
    #   title         info.title verbatim
    #   spec_version  info.version verbatim
    #   oas_version   "3.0.3", "3.1.0"
    #   oas_family    :oas30 | :oas31 (decides which JSON Schema keywords exist)
    #   base_url_env  Derived<String> ENV variable the generated service reads
    #                 the base URL from
    #   spec_file     spec file name as shown in reports (basename, not a path)
    #   overlay_file  overlay file name when one was applied, else nil
    Info = Struct.new(:name, :title, :spec_version, :oas_version, :oas_family,
                      :base_url_env, :spec_file, :overlay_file, keyword_init: true)

    # Vocabulary and checks of Info.
    class Info
      include Node

      FAMILIES = %i[oas30 oas31].freeze

      # @param name [Derived]
      # @param oas_version [String]
      # @param oas_family [Symbol] one of FAMILIES
      # @param base_url_env [Derived, nil]
      # @param title [String, nil]
      # @param spec_version [String, nil]
      # @param spec_file [String, nil]
      # @param overlay_file [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, oas_version:, oas_family:, base_url_env: nil, title: nil,
                     spec_version: nil, spec_file: nil, overlay_file: nil)
        Node.assert_derived!(name, 'provider name')
        Node.assert_text!(oas_version, 'OAS version')
        Node.assert_member!(FAMILIES, oas_family, 'OAS family')
        Node.assert_derived!(base_url_env, 'base URL env') unless base_url_env.nil?
        super
      end

      # @return [Boolean] JSON Schema 2020-12 keywords are native
      def oas31?
        oas_family == :oas31
      end
    end
  end
end
