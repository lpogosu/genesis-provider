# frozen_string_literal: true

module SpecGen
  module Diff
    # Одно отличие между двумя версиями спецификации, увиденное через IR.
    #
    #   kind       что именно изменилось; закрытый словарь KINDS
    #   area       раздел IR, к которому относится изменение
    #   json_path  адрес элемента в новой спецификации, а для исчезнувшего —
    #              в старой
    #   before     значение до, nil у появившегося элемента
    #   after      значение после, nil у исчезнувшего
    #   impact     :code — меняет сгенерированный сервис, :docs — только
    #              INTEGRATION.md и фикстуры, :info — видно только в отчёте
    #
    # `before` и `after` — данные, а не проза: строка, символ, число, список
    # или nil. Печатает их Reporter::DiffLines, поэтому здесь не может
    # появиться текста на одном из языков. Там, где адрес не называет сам
    # элемент (статус в `enum[2]`, правило ошибки, условие), имя ведёт
    # значение через « = »: иначе строка отчёта сообщала бы «внутренний
    # статус: approved -> in_progress», не говоря, у какого статуса.
    Change = Struct.new(:kind, :area, :json_path, :before, :after, :impact, keyword_init: true)

    # Словарь видов изменений и проверки Change.
    class Change
      # Разделы IR в порядке печати: сначала то, что меняет форму запроса,
      # потом то, что меняет чтение ответа, потом ограничения.
      AREAS = %i[operations auth units statuses errors webhooks idempotency fields
                 conditions].freeze
      IMPACTS = %i[code docs info].freeze
      # Значение, которого нет: и в паре «имя = значение», и в колонке отчёта.
      NONE = '—'

      # Вид изменения → [раздел, влияние по умолчанию]. Влияние переопределяет
      # вызывающий там, где оно зависит не от вида, а от самого элемента:
      # необязательное поле без роли в payload не идёт (docs), обязательное
      # идёт (code).
      #
      # Имена видов подчиняются соглашению: `_added` — элемент появился,
      # `_removed` — исчез, всё остальное — переход значения. По этому суффиксу
      # отчёт решает, печатать одно значение или пару «было -> стало».
      KINDS = {
        operation_added: %i[operations code],
        operation_removed: %i[operations code],
        operation_role_changed: %i[operations code],
        operation_endpoint_changed: %i[operations code],
        auth_type_changed: %i[auth code],
        auth_location_changed: %i[auth code],
        auth_param_changed: %i[auth code],
        auth_credentials_changed: %i[auth code],
        currency_changed: %i[units code],
        unit_changed: %i[units code],
        exponent_changed: %i[units code],
        status_added: %i[statuses code],
        status_removed: %i[statuses code],
        status_internal_changed: %i[statuses code],
        error_added: %i[errors code],
        error_removed: %i[errors code],
        error_action_changed: %i[errors code],
        # Код ошибки, объявленный в enum, против кода, встреченного только в
        # примерах: карта строится объединением, поэтому действие то же, а
        # меняется только раздел противоречий в report.md.
        error_declaration_changed: %i[errors info],
        webhook_added: %i[webhooks code],
        webhook_removed: %i[webhooks code],
        event_added: %i[webhooks code],
        event_removed: %i[webhooks code],
        event_status_changed: %i[webhooks code],
        signature_added: %i[webhooks code],
        signature_removed: %i[webhooks code],
        signature_profile_changed: %i[webhooks code],
        signature_header_changed: %i[webhooks code],
        signature_algorithm_changed: %i[webhooks code],
        signature_encoding_changed: %i[webhooks code],
        signature_payload_changed: %i[webhooks code],
        idempotency_header_changed: %i[idempotency code],
        # Заголовок отправляется всегда, даже помеченный необязательным, —
        # меняется таблица методов в INTEGRATION.md, а не сервис.
        idempotency_required_changed: %i[idempotency docs],
        idempotency_conflict_changed: %i[idempotency code],
        field_added: %i[fields code],
        field_removed: %i[fields code],
        field_role_changed: %i[fields code],
        field_requirement_changed: %i[fields code],
        field_condition_changed: %i[fields code],
        # То же условие, но прочитанное иначе: проза 0.50 против
        # dependentRequired 1.00. Ветка в сервисе та же, меняются допущения
        # прогона в INTEGRATION.md.
        field_condition_origin_changed: %i[fields docs],
        parameter_added: %i[fields code],
        parameter_removed: %i[fields code],
        parameter_required_changed: %i[fields code],
        parameter_role_changed: %i[fields code],
        condition_added: %i[conditions code],
        condition_removed: %i[conditions code],
        condition_value_changed: %i[conditions code]
      }.freeze

      # Собирает изменение, подставляя раздел и влияние по виду.
      # @param kind [Symbol] один из ключей KINDS
      # @param json_path [String, nil] адрес элемента
      # @param before [Object, nil] значение до
      # @param after [Object, nil] значение после
      # @param impact [Symbol, nil] влияние, если оно зависит от элемента
      # @return [Change]
      def self.build(kind, json_path:, before: nil, after: nil, impact: nil)
        area, default = KINDS.fetch(kind) do
          raise ArgumentError, "вид изменения: неизвестное значение #{kind.inspect}"
        end
        new(kind: kind, area: area, json_path: json_path, before: before, after: after,
            impact: impact || default)
      end

      # @param kind [Symbol] один из ключей KINDS
      # @param area [Symbol] один из AREAS, обязан соответствовать виду
      # @param impact [Symbol] один из IMPACTS
      # @param json_path [String, nil]
      # @param before [Object, nil]
      # @param after [Object, nil]
      # @raise [ArgumentError]
      def initialize(kind:, area:, impact:, json_path: nil, before: nil, after: nil)
        IR::Node.assert_member!(KINDS.keys, kind, 'вид изменения')
        IR::Node.assert_member!(IMPACTS, impact, 'влияние изменения')
        IR::Node.assert_member!([KINDS.fetch(kind).first], area, "раздел вида #{kind}")
        super
      end

      # Порядок вывода: раздел, затем адрес, затем вид. Значения идут в ключ
      # последними и только как развязка ничьей: `sort_by` в Ruby
      # неустойчива, и два изменения одного вида по одному адресу иначе
      # менялись бы местами от прогона к прогону.
      # @return [Array]
      def sort_key
        [AREAS.index(area), json_path.to_s, kind.to_s, before.to_s, after.to_s]
      end

      # @return [Boolean] элемент появился
      def added?
        kind.to_s.end_with?('_added')
      end

      # @return [Boolean] элемент исчез
      def removed?
        kind.to_s.end_with?('_removed')
      end

      # @return [Boolean] меняет сгенерированный сервис
      def code?
        impact == :code
      end

      # Пара «имя = значение» для элемента, чей адрес его не называет.
      # @param name [Object] имя элемента
      # @param value [Object, nil] значение
      # @return [String]
      def self.pair(name, value)
        text = value.is_a?(Array) ? value.join(', ') : value
        "#{name} = #{text.nil? || text.to_s.empty? ? NONE : text}"
      end
    end
  end
end
