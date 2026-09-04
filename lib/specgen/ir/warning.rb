# frozen_string_literal: true

module SpecGen
  module IR
    # То, что генератор не смог решить или решил с сомнением.
    # Предупреждения — это продукт, а не побочный эффект: report.md
    # оплачивается отдельным критерием, а `--fix` превращает
    # `suggested_overlay` в заготовку overlay, которую пользователь
    # заполняет и возвращает через `--overlay`.
    #
    #   code               один из CODES, машиночитаемый вид проблемы
    #   message            одна фраза для человека
    #   json_path          элемент спецификации, на который надо посмотреть,
    #                      в той же нотации JSONPath, которой Overlay
    #                      адресует свои target, — так предупреждение и его
    #                      исправление указывают на одно и то же место
    #   severity           одна из SEVERITIES
    #   suggested_overlay  фрагмент YAML, который это решил бы, либо nil
    Warning = Struct.new(:code, :message, :json_path, :severity, :suggested_overlay,
                         keyword_init: true)

    # Словарь значений, проверки и порядок Warning.
    class Warning
      include Node

      # По убыванию срочности; на этот порядок опираются сортировка и
      # разделы отчёта.
      SEVERITIES = %i[error warning info].freeze

      # Каждый вид сомнения, который может произвести конвейер. Сгруппированы
      # по стадиям: загрузка и структура, операции, поля и схемы, суммы,
      # статусы и ошибки, вебхуки, идемпотентность, авторизация, overlay.
      #
      # Два кода про авторизацию сообщают не о том, что не удалось вывести, а
      # о том, что спецификация говорит прямо: `auth_absent` (нигде не
      # объявлена никакая авторизация) и `auth_key_in_query` (учётные данные,
      # которые провайдер решил положить в query, где их сохранят логи
      # прокси). Оба идут в отчёт как :info, потому что читателю их всё равно
      # надо увидеть.
      #
      # Два кода про вебхуки различают неполноту и противоречие:
      # `signature_profile_incomplete` — спецификация не назвала параметр
      # подписи, `signature_profile_conflict` — назвала, но не то, что задаёт
      # совпавший профиль справочника. `webhook_event_undeclared` — событие
      # есть в примере, но не в enum поля события: та же дыра, что
      # `status_missing_from_enum`, только у событий.
      #
      # `condition_unclear` — описание операции читается как ограничение по
      # статусу, но не называет ни одного статуса, объявленного в enum;
      # условие взаимодействия не выведено, догадки нет.
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
        webhook_missing webhook_event_unmapped webhook_event_undeclared
        signature_profile_incomplete signature_profile_conflict
        idempotency_header_missing idempotency_dedup_unclear
        auth_unknown auth_multiple_schemes auth_absent auth_key_in_query
        overlay_conflict overlay_target_missing
        contract_gap condition_unclear
      ].freeze

      # @param code [Symbol] один из CODES
      # @param message [String]
      # @param json_path [String, nil] JSONPath элемента, о котором речь
      # @param severity [Symbol] одна из SEVERITIES
      # @param suggested_overlay [String, nil] фрагмент YAML, который это
      #   исправил бы
      # @raise [ArgumentError] при неизвестном коде или серьёзности
      def initialize(code:, message:, json_path: nil, severity: :warning, suggested_overlay: nil)
        Node.assert_member!(CODES, code, 'код предупреждения')
        Node.assert_text!(message, 'текст предупреждения')
        Node.assert_member!(SEVERITIES, severity, 'серьёзность предупреждения')
        super
        freeze
      end

      # Детерминированный порядок: сначала срочность, потом место, потом вид,
      # чтобы два прогона на одной спецификации давали байт-в-байт
      # одинаковые отчёты.
      # @return [Array]
      def sort_key
        [SEVERITIES.index(severity), json_path.to_s, code.to_s]
      end

      # @return [Boolean] генерацию нельзя считать завершённой
      def blocking?
        severity == :error
      end

      # @return [Boolean] готовый фрагмент overlay доступен
      def fixable?
        !suggested_overlay.nil?
      end

      # @return [String] одна строка report.md
      def to_s
        [severity.to_s.upcase, json_path, message].compact.join(' ')
      end
    end
  end
end
