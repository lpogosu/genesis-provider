# frozen_string_literal: true

module SpecGen
  module Reporter
    # Секция карты ошибок в сводке: сколько кодов провайдера объявлено в enum
    # и сколько нашлось только в примерах, где дедупликация, затем по строке
    # на код провайдера с действием и по строке на операцию с её HTTP-кодами.
    #
    # Обоснование под --explain печатается у правил по коду провайдера и у
    # дедупликации: там решение нетривиально. Правила по HTTP-коду читаются
    # из справочника одной записью, и их обоснование повторяло бы номер кода.
    class ErrorLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] печатать обоснование под правилами по коду
      def initialize(profile, explain: false)
        @profile = profile
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return [Texts.t('summary.errors_none')] if @profile.error_map.empty?

        [headline] + code_lines + http_lines
      end

      private

      def headline
        declared = code_rules.count(&:declared?)
        Texts.t('summary.errors', declared: declared, undeclared: code_rules.size - declared,
                                  dedup: dedup_text)
      end

      def dedup_text
        dedups = @profile.error_map.select(&:dedup?)
        return '' if dedups.empty?

        Texts.t('summary.errors_dedup', status: dedups.map(&:http_status).uniq.join(', '),
                                        operations: dedups.map(&:operation).compact.uniq.join(', '))
      end

      def code_rules
        @code_rules ||= @profile.error_map.select do |rule|
          rule.provider_code && rule.http_status.nil?
        end
      end

      def http_rules
        @profile.error_map.select(&:http_status)
      end

      def code_lines
        width = code_rules.map { |rule| rule.provider_code.size }.max || 0
        code_rules.flat_map do |rule|
          line = "#{INDENT}#{rule.provider_code.ljust(width)}  #{Format.derived(rule.action)}"
          ["#{line}  [#{seen(rule)}]", *evidence(rule)]
        end
      end

      def seen(rule)
        rule.seen_in.map { |place| Texts.t("seen_in.#{place}") }.join(' + ')
      end

      # Операции в порядке спецификации, общие правила последними.
      def http_lines
        grouped = http_rules.group_by(&:operation)
        keys = ordered_keys(grouped)
        width = keys.map { |key| label(key).size }.max || 0
        keys.flat_map { |key| http_line(label(key), grouped[key], width) }
      end

      def ordered_keys(grouped)
        keys = @profile.operations.map(&:key).select { |key| grouped.key?(key) }
        keys += grouped.keys - keys - [nil]
        grouped.key?(nil) ? keys << nil : keys
      end

      def label(key)
        key || Texts.t('summary.errors_generic')
      end

      def http_line(label, rules, width)
        listed = rules.map { |rule| rule_text(rule) }.join(', ')
        ["#{INDENT}#{label.ljust(width)}  #{listed}",
         *rules.select(&:dedup?).flat_map { |rule| evidence(rule) }]
      end

      def evidence(rule)
        Format.evidence(rule.action, explain: @explain, depth: 2)
      end

      def rule_text(rule)
        text = "#{rule.http_status} #{rule.action.value}"
        rule.retry_after ? "#{text} #{Texts.t('summary.retry_after')}" : text
      end
    end
  end
end
