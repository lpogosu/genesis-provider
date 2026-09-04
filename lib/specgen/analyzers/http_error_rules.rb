# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Правила карты ошибок по HTTP-кодам: для каждой операции — каждый
    # объявленный ответ вне 2xx, плюс общие правила для кодов, которые
    # объявлены у соседних операций, но пропущены у этой.
    #
    # Действие даёт rules/errors.yml по точному коду или классу; единственное
    # исключение — код конфликта, чья схема совпала со схемой успеха: это
    # дедупликация (DedupReader), она структурна и побеждает справочник.
    # Retry-After читается из объявленных заголовков ответа.
    #
    # Пропущенный код не остаётся дырой: у GET /payouts/{id} нет 429 и 500,
    # которые объявлены у POST /payouts, а провайдер вернёт их всё равно.
    # Для таких кодов строится общее правило (operation: nil) и пишется
    # справка undeclared_status_code — достроено, а не угадано.
    class HttpErrorRules
      SUCCESS = (200..299)

      # @param data [Hash] разрешённый документ
      # @param book [Rules::ErrorsBook]
      # @param conflict_status [Integer, nil] код повтора из rules/idempotency.yml
      def initialize(data:, book:, conflict_status:)
        @data = data
        @book = book
        @conflict = conflict_status
        @rules = []
        @notes = []
        @declared = {}
        @paths = {}
        @seen = {}
      end

      # @return [Array(Array<IR::ErrorRule>, Array<Array>)] правила и заметки
      #   [код предупреждения, сообщение, JSONPath, серьёзность]
      def call
        Operations.each(@data) { |path, verb, node| operation(path, verb, node) }
        gaps
        [@rules, @notes]
      end

      private

      # Операция с `security: []` — входящий вызов провайдера к нам; её ответы
      # пишет сгенерированный сервис, а не провайдер, и в карту ошибок они
      # не входят.
      def operation(path, verb, node)
        return if node['security'].is_a?(Array) && node['security'].empty?

        key = SchemaNaming.operation_key(node['operationId'], verb, path)
        at = SpecLoader::JsonPath.build([Operations::PATHS, path, verb])
        responses = node['responses']
        return unless responses.is_a?(Hash)

        dedup = DedupReader.new(node: node, key: key, conflict_status: @conflict, at: at).call
        @paths[key] = at
        @declared[key] = responses.filter_map do |status, response|
          response_rule(key, status, response, at, dedup)
        end
      end

      # @return [Integer, nil] код, для которого записано правило
      def response_rule(key, status, response, at, dedup)
        code = Integer(status.to_s, exception: false)
        return nil if code.nil? || SUCCESS.cover?(code)

        where = "#{at}.responses#{SpecLoader::JsonPath.segment(status.to_s)}"
        retry_after = retry_after?(response)
        @seen[code] ||= [key, retry_after]
        action = dedup_action(dedup, code) || status_action(code, where)
        @rules << IR::ErrorRule.new(http_status: code, operation: key, action: action,
                                    retry_after: retry_after, seen_in: [:response],
                                    json_path: where)
        code
      end

      def dedup_action(dedup, code)
        return nil unless dedup&.dedup && dedup.status == code

        IR::Derived.structural(:dedup, evidence: DedupReader.evidence(dedup))
      end

      # @param suffix [String] добавка к обоснованию общего правила
      def status_action(code, where, suffix = '')
        action, entry = @book.action_for_status(code)
        if action
          evidence = t('http_evidence', code: code, entry: entry, action: action)
          return IR::Derived.registry(action, evidence: evidence + suffix)
        end

        what = t('what_status', code: code)
        @notes << [:error_action_unknown, unknown_message(what), where, :warning]
        IR::Derived.registry(@book.default_action, confidence: @book.default_confidence,
                                                   evidence: default_evidence(what) + suffix)
      end

      def unknown_message(what)
        t('action_unknown_message', what: what, action: @book.default_action,
                                    confidence: format('%.2f', @book.default_confidence))
      end

      def default_evidence(what)
        t('default_evidence', what: what, action: @book.default_action)
      end

      def retry_after?(response)
        headers = response.is_a?(Hash) ? response['headers'] : nil
        headers.is_a?(Hash) && headers.keys.any? { |header| @book.retry_after?(header.to_s) }
      end

      # Код, объявленный у соседей, но не здесь, получает общее правило.
      def gaps
        union = @declared.values.flatten.uniq
        needed = []
        @declared.each do |key, own|
          missing = (union - own).sort
          next if missing.empty?

          needed |= missing
          @notes << [:undeclared_status_code, gap_message(key, missing), @paths[key], :info]
        end
        needed.sort.each { |code| generic(code) }
      end

      def gap_message(key, missing)
        operations = missing.map { |code| @seen[code].first }.uniq.join(', ')
        t('gap_message', key: key, codes: missing.join(', '), operations: operations)
      end

      def generic(code)
        operation, retry_after = @seen[code]
        action = status_action(code, nil, t('generic_suffix', operation: operation))
        @rules << IR::ErrorRule.new(http_status: code, operation: nil, action: action,
                                    retry_after: retry_after, seen_in: [:response])
      end

      def t(key, **params)
        Texts.t("analyzers.error.#{key}", **params)
      end
    end
  end
end
