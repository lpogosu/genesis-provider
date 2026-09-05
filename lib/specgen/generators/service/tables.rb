# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Замороженные таблицы сервиса: STATUS_MAP, ERROR_MAP, RETRY_POLICY,
      # EVENT_MAP. Таблицы, а не цепочки if: их видно на code review и легко
      # сверить с INTEGRATION.md. Ключи отсортированы — вывод не зависит от
      # порядка обхода.
      #
      # RETRY_POLICY — данные, не механизм: какие действия повторять, какие
      # коды несут Retry-After. Сами ретраи, очереди и алерты — инфраструктура
      # платформы.
      class Tables
        # Действия из IR::Roles::ERROR_ACTION, при которых платформа
        # повторяет запрос.
        RETRY_ACTIONS = %i[retry retry_backoff].freeze
        # Отступ записи внутри константы-хеша.
        INDENT = 6

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @profile = ctx.profile
        end

        # Строки STATUS_MAP как данные: по одной на статус провайдера, без
        # повторов, по алфавиту. INTEGRATION.md печатает ровно этот список,
        # поэтому таблица документа совпадает с константой по построению.
        # @return [Array<IR::StatusMapping>]
        def status_mappings
          @profile.status_map.uniq(&:provider_status).sort_by(&:provider_status)
        end

        # @return [Array<IR::WebhookEvent>] строки EVENT_MAP как данные
        def events
          webhook = @ctx.webhook
          return [] if webhook.nil?

          webhook.events.uniq(&:name).sort_by(&:name)
        end

        # @return [Array<String>] записи STATUS_MAP: статус провайдера → символ
        def status_lines
          render(status_mappings.map { |m| mapped_entry(m.provider_status, m.internal, 'status') })
        end

        # @return [Array<String>] записи ERROR_MAP: код провайдера или HTTP-код
        #   → действие; дедупликация сюда не входит, у неё свой код DEDUP_STATUS
        def error_lines
          codes = code_rules.map { |rule| error_entry(Ruby.str(rule.provider_code), rule) }
          http = http_rules.map { |rule| error_entry(Ruby.number(rule.http_status), rule) }
          entries = []
          entries.push(section('error_map_codes'), *codes) unless codes.empty?
          entries.push(section('error_map_http'), *http) unless http.empty?
          render(entries)
        end

        # Правила одной операции, расходящиеся с общими: у большинства
        # спецификаций пусто, тогда константа не печатается.
        # @return [Array<String>] записи ERROR_MAP_BY_OPERATION
        def operation_error_lines
          grouped = specific_rules.group_by(&:operation).sort
          render(grouped.map do |key, rules|
            sorted = rules.sort_by(&:http_status)
            inner = sorted.map { |r| error_entry(Ruby.number(r.http_status), r) }
            [[], ["#{Ruby.str(key)} => {", *Ruby.indent(render(inner), 2), '}']]
          end)
        end

        # RETRY_POLICY как данные: действия, HTTP-коды, заголовок паузы и коды,
        # которые его несут.
        # @return [Hash{Symbol => Object}]
        def retry_policy
          retried = http_rules.select { |r| RETRY_ACTIONS.include?(r.action.value) }
          header = retry_after_statuses.empty? ? nil : @ctx.rules.errors.retry_after_header
          { actions: RETRY_ACTIONS, statuses: retried.map(&:http_status),
            retry_after_header: header, retry_after_statuses: retry_after_statuses }
        end

        # @return [Array<String>] записи RETRY_POLICY
        def retry_lines
          render(retry_policy.map { |key, value| [[], ["#{key}: #{Ruby.literal(value)}"]] })
        end

        # Коды платформы, которыми сервис отказывает: первый аргумент failure.
        # Таблица печатается целиком, а не по объявленным кодам, — провайдер
        # вправе ответить кодом, которого спецификация не объявляла.
        # @return [Hash{Integer => Symbol}]
        def failure_codes
          @ctx.platform.failure_codes.by_http
        end

        # @return [Hash{Symbol => Symbol}] действие ERROR_MAP → код платформы
        def failure_codes_by_action
          @ctx.platform.failure_codes.by_action
        end

        # @return [Array<String>] записи FAILURE_CODES
        def failure_code_lines
          render(failure_codes.map do |status, code|
            [[], ["#{Ruby.number(status)} => #{Ruby.sym(code)}"]]
          end)
        end

        # @return [Array<String>] записи FAILURE_CODES_BY_ACTION
        def failure_action_lines
          render(failure_codes_by_action.map do |action, code|
            [[], ["#{Ruby.key(action)} #{Ruby.sym(code)}"]]
          end)
        end

        # @return [Array<String>] записи EVENT_MAP: событие вебхука → внутренний
        #   статус; событие без статуса остаётся с nil и TODO
        def event_lines
          render(events.map { |e| mapped_entry(e.name, e.internal_status, 'event') })
        end

        # @return [Array<IR::ErrorRule>] правила по коду ошибки провайдера,
        #   по одному на код, по алфавиту — секция «по коду» ERROR_MAP
        def code_rules
          @code_rules ||= @profile.sorted_error_map.select(&:provider_code).reject(&:dedup?)
                                  .uniq(&:provider_code).sort_by(&:provider_code)
        end

        # @return [Array<IR::ErrorRule>] общие правила по HTTP-коду — секция
        #   «по HTTP-коду» ERROR_MAP
        def http_rules
          @http_rules ||= @profile.sorted_error_map
                                  .select { |r| r.generic? && r.provider_code.nil? }
                                  .select(&:http_status).reject(&:dedup?)
                                  .uniq(&:http_status).sort_by(&:http_status)
        end

        # @return [Array<IR::ErrorRule>] правила операции, расходящиеся с
        #   общими, — ERROR_MAP_BY_OPERATION
        def specific_rules
          @profile.sorted_error_map.select { |r| r.operation && r.http_status && !r.provider_code }
                  .reject(&:dedup?).reject do |rule|
            generic = http_rules.find { |r| r.http_status == rule.http_status }
            generic && generic.action.value == rule.action.value
          end
        end

        # @return [Array<Integer>] коды ответов, объявляющие заголовок паузы
        def retry_after_statuses
          @retry_after_statuses ||= @profile.conditions.select { |c| c.kind == :retry_after }
                                            .filter_map { |c| c.value.value }.uniq.sort
        end

        private

        # @param entries [Array<Array(Array<String>, Array<String>)>]
        #   комментарии и строки каждой записи
        def render(entries)
          entries.each_with_index.flat_map do |(comments, lines), index|
            body = lines.dup
            body[-1] = "#{body[-1]}," unless index == entries.size - 1 || body.empty?
            comments + body
          end
        end

        def section(key)
          [comment(@ctx.t(key)), []]
        end

        # Запись «ключ → внутренний статус»; невыведенный статус — nil и TODO.
        def mapped_entry(name, internal, kind)
          key = Ruby.str(name)
          return [[], ["#{key} => #{Ruby.sym(internal.value)}"]] if internal.known?

          text = @ctx.t("#{kind}_unmapped", evidence: internal.evidence)
          [comment(text, prefix: '# TODO: '), ["#{key} => nil"]]
        end

        def error_entry(key, rule)
          action = rule.action
          comments = []
          if @ctx.doubtful?(action)
            comments = comment(@ctx.t('error_action_doubt', confidence: @ctx.source_label(action)))
          end
          [comments, ["#{key} => #{Ruby.sym(action.value)}"]]
        end

        def comment(text, prefix: '# ')
          Ruby.comment(text, width: Ruby::WIDTH - INDENT, prefix: prefix)
        end
      end
    end
  end
end
