# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Коды ошибок провайдера — объединение enum поля кода и значений из
    # примеров всех ответов.
    #
    # Спецификация редко перечисляет в enum всё, что возвращает: в выданной
    # спеке unauthorized, not_found и invalid_status есть только в примерах,
    # а bank_unavailable, amount_limit_exceeded и internal_error — только в
    # enum. Карта ошибок обязана знать и то и другое, а отчёт — сказать о
    # расхождении; поэтому каждый код помнит, где его видели, и путь до
    # первого места.
    #
    # Поле кода узнаётся структурно через RoleLookup: точный синоним роли
    # error_code или токен `code` под родителем-ошибкой (`error.code`,
    # `PayoutError.code`). Голое `code` без такого родителя кодом ошибки не
    # считается — так называют и код валюты, и код банка.
    class ErrorCodeReader
      # Один код ошибки.
      #
      #   value      код как написан
      #   seen_in    подмножество IR::ErrorRule::SEEN_IN: :enum и/или :example
      #   json_path  первое место, где код встретился (enum раньше примеров)
      Code = Struct.new(:value, :seen_in, :json_path, keyword_init: true)

      EXTENSION = 'x-specgen-error-actions'

      # @return [String, nil] JSONPath первого поля кода ошибки с enum
      attr_reader :field_path
      # @return [Hash{String => Object}] `x-specgen-error-actions` всех полей
      #   кода: код провайдера => действие
      attr_reader :overrides

      # @param data [Hash] разрешённый документ
      # @param lookup [RoleLookup]
      def initialize(data:, lookup:)
        @data = data
        @lookup = lookup
        @codes = {}
        @field_path = nil
        @overrides = {}
      end

      # @return [ErrorCodeReader] сам объект с заполненными кодами
      def call
        from_enums
        from_examples
        self
      end

      # @return [Array<Code>] коды из enum в порядке enum, затем коды только
      #   из примеров в порядке спецификации
      def codes
        @codes.values
      end

      private

      def from_enums
        SchemaIndex.new(@data).each_field do |entry, name, node, path|
          enum = node['enum']
          next unless enum.is_a?(Array) && @lookup.error_code?(name, [entry.name])

          @field_path ||= path
          @overrides = node[EXTENSION].merge(@overrides) if node[EXTENSION].is_a?(Hash)
          enum.each_with_index do |value, index|
            text = ConstraintReader.enum_text(value)
            record(text, :enum, "#{path}.enum[#{index}]") if text
          end
        end
      end

      def from_examples
        ExampleReader.each_in_document(@data) do |example|
          parents = [example.schema].compact
          ExampleReader.each_pair(example.value, example.json_path, parents) do |key, value, up, at|
            record(value, :example, at) if value.is_a?(String) && @lookup.error_code?(key, up)
          end
        end
      end

      def record(value, place, at)
        code = (@codes[value] ||= Code.new(value: value, seen_in: [], json_path: at))
        code.seen_in << place unless code.seen_in.include?(place)
      end
    end
  end
end
