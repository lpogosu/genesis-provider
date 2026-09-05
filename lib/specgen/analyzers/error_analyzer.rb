# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.error_map: что сгенерированный сервис делает, увидев
    # заданный HTTP-код или код ошибки провайдера.
    #
    # Правила двух видов. По HTTP-коду — для каждой операции и каждого её
    # ответа вне 2xx (HttpErrorRules), причём код конфликта со схемой успеха
    # получает :dedup: по черновику IETF Idempotency-Key это повтор, а не
    # ошибка. По коду провайдера — для объединения enum поля кода ошибки и
    # значений из примеров (ErrorCodeReader): код, который есть только в
    # примерах, — предупреждение error_code_undeclared, код только в enum —
    # справка error_code_unused, но правило строится обоим.
    #
    # Само действие — данные из rules/errors.yml, а не ветка здесь: точный
    # HTTP-код, класс кода, шаблон имени. Код, не совпавший ни с чем,
    # получает действие по умолчанию с низкой уверенностью и предупреждение
    # error_action_unknown с фрагментом overlay (`x-specgen-error-actions`
    # на поле кода), который читается здесь же как источник :overlay.
    class ErrorAnalyzer < Base
      # Заполняет `profile.error_map`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @book = rules.errors
        http_rules
        code_rules
        profile
      end

      private

      def http_rules
        listed, notes = HttpErrorRules.new(data: data, book: @book,
                                           conflict_status: rules.idempotency.conflict_status).call
        profile.error_map.concat(listed)
        notes.each do |code, message, at, severity|
          profile.warn(code, message, json_path: at, severity: severity)
        end
      end

      def code_rules
        reader = ErrorCodeReader.new(data: data, lookup: RoleLookup.new(rules, data)).call
        reader.codes.each do |code|
          profile.error_map << IR::ErrorRule.new(provider_code: code.value, seen_in: code.seen_in,
                                                 action: code_action(code, reader),
                                                 json_path: code.json_path)
          report(code, reader)
        end
      end

      def code_action(code, reader)
        override = reader.overrides[code.value]
        overlay = override && overlay_action(code, override)
        return overlay if overlay

        rule = @book.rule_for_code(code.value)
        return unknown_action(code, reader) if rule.nil?

        evidence = t('pattern_evidence', code: code.value, name: rule.name, action: rule.action)
        IR::Derived.registry(rule.action, confidence: @book.pattern_confidence, evidence: evidence)
      end

      def overlay_action(code, value)
        action = value.to_s.to_sym
        if IR::Roles::ERROR_ACTION.include?(action)
          evidence = t('overlay_evidence', code: code.value, action: action)
          return IR::Derived.overlay(action, evidence: evidence)
        end

        profile.warn(:spec_element_unsupported,
                     t('overlay_bad', code: code.value, value: value.inspect,
                                      allowed: IR::Roles::ERROR_ACTION.join(' | ')),
                     json_path: code.json_path)
        nil
      end

      def unknown_action(code, reader)
        what = t('what_code', code: code.value)
        default = @book.default_action
        fragment = reader.field_path && t('overlay_fragment', path: reader.field_path,
                                                              code: code.value)
        message = t('action_unknown_message', what: what, action: default,
                                              confidence: format('%.2f', @book.default_confidence))
        profile.warn(:error_action_unknown, message, json_path: code.json_path,
                                                     suggested_overlay: fragment)
        IR::Derived.registry(default, confidence: @book.default_confidence,
                                      evidence: t('default_evidence', what: what, action: default))
      end

      # Код только в примерах и код только в enum — два разных расхождения
      # спецификации с самой собой, и отчёт называет оба.
      def report(code, reader)
        if !code.seen_in.include?(:enum)
          where = reader.field_path ? t('undeclared_where', path: reader.field_path) : ''
          profile.warn(:error_code_undeclared,
                       t('undeclared_message', code: code.value, where: where),
                       json_path: code.json_path)
        elsif !code.seen_in.include?(:example)
          profile.warn(:error_code_unused, t('unused_message', code: code.value),
                       json_path: code.json_path, severity: :info)
        end
      end

      def t(key, **params)
        Texts.t("analyzers.error.#{key}", **params)
      end
    end
  end
end
