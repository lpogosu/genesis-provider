# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Успешный путь дедупликации: ответ с кодом конфликта, чья схема совпадает
    # со схемой успешного ответа той же операции.
    #
    # Черновик IETF draft-ietf-httpapi-idempotency-key-header говорит: при
    # повторном запросе с тем же ключом ресурс возвращает результат ранее
    # завершённой операции. Значит, 409 на POST /payouts, отдающий
    # PayoutResponse, — это «уже создано, вот результат», а не ошибка. Но
    # 409 на POST /payouts/{id}/cancel, отдающий ErrorResponse, — обычный
    # отказ. Различить их можно только по схеме, поэтому проверяются схемы,
    # а не коды, и делает это один общий reader: ErrorAnalyzer кладёт
    # действие :dedup в карту ошибок, IdempotencyAnalyzer — код конфликта в
    # профиль идемпотентности, и оба обязаны решить одинаково.
    class DedupReader
      # Что найдено у одной операции.
      #
      #   dedup           схема ответа с кодом конфликта совпала со схемой успеха
      #   status          код конфликта из rules/idempotency.yml
      #   success_status  код первого ответа 2xx
      #   success_schema  имя схемы успешного ответа или nil
      #   conflict_schema имя схемы ответа с кодом конфликта или nil
      #   json_path       JSONPath ответа с кодом конфликта
      Result = Struct.new(:dedup, :status, :success_status, :success_schema, :conflict_schema,
                          :json_path, keyword_init: true)

      SUCCESS = '2'

      # @param node [Hash] Operation Object
      # @param key [String] Operation#key, для имён инлайновых схем
      # @param conflict_status [Integer, nil] код повтора из справочника
      # @param at [String] JSONPath операции
      def initialize(node:, key:, conflict_status:, at:)
        @node = node
        @key = key
        @status = conflict_status
        @at = at
      end

      # @return [Result, nil] nil, если операция не объявляет ответ с кодом
      #   конфликта
      def call
        responses = @node['responses']
        return nil unless @status && responses.is_a?(Hash)

        conflict = responses[@status.to_s]
        return nil unless conflict.is_a?(Hash)

        success_status, success = responses.find do |code, body|
          code.to_s.start_with?(SUCCESS) && body.is_a?(Hash)
        end
        build(conflict, success, success_status)
      end

      # @param result [Result] с dedup равным true
      # @return [String] обоснование для отчёта, общее для обоих анализаторов
      def self.evidence(result)
        Texts.t('analyzers.dedup.evidence', status: result.status, schema: result.success_schema,
                                            success_status: result.success_status)
      end

      private

      def build(conflict, success, success_status)
        success_schema = schema_of(success, success_status)
        conflict_schema = schema_of(conflict, @status)
        Result.new(dedup: !success_schema.nil? && success_schema == conflict_schema,
                   status: @status, success_status: success_status,
                   success_schema: success_schema, conflict_schema: conflict_schema,
                   json_path: "#{@at}.responses#{SpecLoader::JsonPath.segment(@status.to_s)}")
      end

      def schema_of(response, code)
        return nil unless response.is_a?(Hash)

        content = response['content']
        ContentReader.schema_name(content, ContentReader.media_type(content),
                                  [@key, 'responses', code.to_s])
      end
    end
  end
end
