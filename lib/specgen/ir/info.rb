# frozen_string_literal: true

module SpecGen
  module IR
    # Кто провайдер и из какого документа это выведено.
    #
    #   name          Derived<String> — slug провайдера для имён класса и
    #                 файла, например "acmepay" (из --provider или info.title)
    #   title         info.title дословно
    #   spec_version  info.version дословно
    #   oas_version   "3.0.3", "3.1.0"
    #   oas_family    :oas30 | :oas31 (решает, какие ключевые слова JSON
    #                 Schema доступны)
    #   base_url_env  Derived<String> — переменная окружения, из которой
    #                 сгенерированный сервис читает базовый URL
    #   spec_file     имя файла спецификации, как его показывают отчёты (имя
    #                 файла, не путь)
    #   overlay_file  имя файла overlay, если он применялся, иначе nil
    Info = Struct.new(:name, :title, :spec_version, :oas_version, :oas_family,
                      :base_url_env, :spec_file, :overlay_file, keyword_init: true)

    # Словарь значений и проверки Info.
    class Info
      include Node

      FAMILIES = %i[oas30 oas31].freeze

      # @param name [Derived]
      # @param oas_version [String]
      # @param oas_family [Symbol] одно из FAMILIES
      # @param base_url_env [Derived, nil]
      # @param title [String, nil]
      # @param spec_version [String, nil]
      # @param spec_file [String, nil]
      # @param overlay_file [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, oas_version:, oas_family:, base_url_env: nil, title: nil,
                     spec_version: nil, spec_file: nil, overlay_file: nil)
        Node.assert_derived!(name, 'имя провайдера')
        Node.assert_text!(oas_version, 'версия OAS')
        Node.assert_member!(FAMILIES, oas_family, 'семейство OAS')
        Node.assert_derived!(base_url_env, 'переменная базового URL') unless base_url_env.nil?
        super
      end

      # @return [Boolean] ключевые слова JSON Schema 2020-12 доступны нативно
      def oas31?
        oas_family == :oas31
      end
    end
  end
end
