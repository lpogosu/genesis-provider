# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 4: маппинг статусов и событий. Строки — ровно те, что
      # Service::Tables печатает в STATUS_MAP и EVENT_MAP, в том же порядке.
      class Statuses < Base
        # @return [Array<String>] заголовки обеих таблиц
        def headers(first)
          [t(first), t('internal_col'), t('source_col'), t('confidence_col')]
        end

        # @return [Array<Array<String>>] статус провайдера → внутренний
        def status_rows
          parts[:tables].status_mappings.map do |mapping|
            row(mapping.provider_status, mapping.provider_status, mapping.internal)
          end
        end

        # @return [Array<Array<String>>] событие вебхука → внутренний
        def event_rows
          parts[:tables].events.map do |event|
            row(event.name, event.provider_status || event.name, event.internal_status)
          end
        end

        # @return [String, nil] почему таблицы статусов нет
        def status_note
          return nil unless status_rows.empty?

          t('status_none', report: report)
        end

        # @return [String, nil] почему таблицы событий нет
        def event_note
          return nil if ctx.webhook

          t('events_none', fetch: code(contract.method_for(:fetch_status)&.name.to_s))
        end

        private

        def row(name, status, internal)
          return [code(name), EMPTY, t('status_unmapped'), EMPTY] unless internal.known?

          [code(name), code(internal.value), source_text(status, internal),
           format('%.2f', internal.confidence)]
        end

        def source_text(status, internal)
          if internal.source == :registry && ctx.rules.statuses.canonical?(status)
            return t('status_source_canonical')
          end

          t("status_source_#{internal.source}")
        end
      end
    end
  end
end
