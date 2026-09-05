# frozen_string_literal: true

require 'psych'

module SpecGen
  module Generators
    module Integration
      # Раздел 6: параметры подключения, выведенные из спецификации, —
      # адрес, переменная окружения, ключи учётных данных, валюты, единицы и
      # границы суммы, ограничения полей, путь и заголовок уведомлений.
      #
      # Раньше раздел назывался «конфигурация ProviderGateway» и предлагал
      # платформе форму регистрации. Эксперты 5 сентября 2026 сказали, что
      # такой конфиг платформе не нужен, а «адрес, авторизация и т.д. должны
      # браться из open api документа провайдера». Поэтому здесь больше не
      # предлагается интерфейс: это сводка того, что инструмент вывел из
      # спецификации и подставил в сервис. Значения считает тот же код, что и
      # предпроверки, — документ совпадает с кодом по построению.
      class Gateway < Base
        # Ключи YAML по виду условия.
        KEYS = { field_max_length: 'max_length', field_pattern: 'pattern', field_enum: 'enum',
                 min_amount: 'minimum', max_amount: 'maximum' }.freeze
        # Сколько строк печатать в таблице «куда мапить»: у чужих
        # спецификаций полей бывает под три сотни.
        MAX_ROWS = 40

        # Таблица «куда мапить»: для каждого поля тела запроса — выражение
        # платформы, которое его заполняет, а для поля без выражения пустая
        # ячейка под ручной маппинг. Эксперты кейса 5 сентября 2026
        # (вопрос 25) просили именно явное место маппинга в INTEGRATION.md.
        # @return [Array<Array<String>>] строки таблицы
        def mapping_rows
          rows = mapping_entries.map { |entry| mapping_row(entry) }
          return rows if rows.size <= MAX_ROWS

          rows.take(MAX_ROWS) + [[t('mapping_more', count: rows.size - MAX_ROWS), '', '', '']]
        end

        # @return [Boolean] есть что печатать
        def mapping?
          !mapping_entries.empty?
        end

        # @return [Array<String>] строки YAML-фрагмента
        def lines
          ['providers:', "  #{ctx.naming.slug}:",
           "    service: #{ctx.full_class_name}",
           "    base_url: #{scalar(ctx.sandbox_url)}  # #{t('gateway_env', env: ctx.base_url_env)}",
           "    credentials: #{inline(credential_keys)}",
           "    request_methods: #{inline(contract.request_method_values)}",
           "    currencies: #{currencies}",
           *amount_lines, *field_lines, *webhook_lines]
        end

        private

        # Поля тела запроса операции создания: те же и в том же порядке, что
        # печатает build_payload. Поле группы реквизитов раскрывается по
        # веткам способов выплаты — выражение у него своё в каждой.
        def mapping_entries
          @mapping_entries ||= begin
            fields = Generators::SchemaFields.new(ctx)
            fields.of(ctx.create_operation&.request_schema).flat_map { |entry| expand(entry) }
          end
        end

        def expand(entry)
          branches = requisites.branches.select do |branch|
            branch.fields.any? { |field| field.equal?(entry.field) }
          end
          return [[entry, nil]] if branches.empty?

          branches.map { |branch| [entry, branch] }
        end

        def requisites
          parts[:requisites]
        end

        def mapping_row((entry, branch))
          field = entry.field
          role = field.role.known? ? code(field.role.value) : t('mapping_no_role')
          [code(entry.path), role, branch ? code(branch.key || branch.value) : t('none'),
           mapping_expression(field, branch)]
        end

        # Пустая ячейка — это и есть место под ручной маппинг: выражения
        # платформы для поля нет, а выдумывать его запрещено.
        def mapping_expression(field, branch)
          expression = if branch then requisites.expression(field, branch)
                       elsif field.role.known?
                         ctx.accessor(field.role.value) ||
                           ctx.currency_constant_for(field.role.value)
                       end
          expression ? code(expression) : t('mapping_manual')
        end

        # Ключи provider.credentials, которые читает сервис: авторизация и,
        # если есть уведомления, секрет подписи.
        def credential_keys
          keys = parts[:authorization].credential_keys.map(&:to_s)
          keys << parts[:signature].value(:secret_key).to_s if ctx.webhook
          keys.uniq
        end

        def precheck
          parts[:precheck]
        end

        def conditions
          precheck.conditions
        end

        # Валюта запроса: платформа её не сообщает, сервис берёт её из
        # спецификации константой CURRENCY — здесь видно, откуда взялся код.
        def currencies
          currency = profile.units&.currency
          return known_currency(currency) if currency&.known?

          values = currency_enum ? Array(currency_enum.value.value) : []
          "#{inline(values)}  # TODO: #{t('currencies_unknown')}"
        end

        def known_currency(currency)
          "#{inline([currency.value])}  # #{t('gateway_currency', evidence: currency.evidence)}"
        end

        def currency_enum
          conditions.find { |c| c.kind == :field_enum && precheck.role_of(c) == :currency }
        end

        def amount_lines
          units = profile.units
          lines = ['    amount:', "      platform_unit: #{contract.amount_unit}"]
          if units&.known?
            lines << "      provider_unit: #{units.unit.value}"
            lines << "      multiplier: #{units.multiplier}  # #{units.exponent.evidence}"
          else
            lines << "      multiplier: 1  # TODO: #{t('units_unknown')}"
          end
          lines + limit_lines
        end

        def limit_lines
          amount_conditions.map do |c|
            value = precheck.amount(c.value.value)
            "      #{KEYS.fetch(c.kind)}: #{value}  # #{precheck.description(c)}"
          end
        end

        def amount_conditions
          conditions.select { |c| Service::Precheck::AMOUNT_KINDS.include?(c.kind) }
        end

        # Ограничения полей по имени поля спецификации, с ролью в комментарии:
        # одну роль могут нести несколько полей (два поля типа получателя у
        # Adyen), а ключи YAML внутри одного объекта повторяться не могут.
        def field_lines
          fields = conditions - amount_conditions
          return [] if fields.empty?

          entries = fields.group_by(&:field).flat_map { |name, list| field_entry(name, list) }
          ['    fields:'] + entries
        end

        def field_entry(name, list)
          first, rest = split_by_kind(list)
          role = precheck.role_of(first.first)
          line = "      #{name}: { #{pairs(first)} }"
          line += "  # #{t('gateway_role', role: role)}" if role
          [line] + rest.map { |c| "      # #{t('gateway_also', field: name, pair: pairs([c]))}" }
        end

        # Первое условие каждого вида — в запись, повторы вида — в комментарий.
        def split_by_kind(list)
          seen = {}
          list.partition { |c| seen.key?(c.kind) ? false : (seen[c.kind] = true) }
        end

        def pairs(list)
          list.map { |c| "#{KEYS.fetch(c.kind)}: #{scalar(c.value.value)}" }.join(', ')
        end

        def webhook_lines
          webhook = ctx.webhook
          return [] if webhook.nil?

          lines = ['    webhook:', "      path: #{scalar(webhook.path)}"]
          header = parts[:signature].value(:header)
          lines << "      signature_header: #{scalar(header)}" if header
          lines
        end

        # Скаляр или список в потоковой записи YAML, через Psych, чтобы
        # кавычки и экранирование были по стандарту.
        def scalar(value)
          return inline(value) if value.is_a?(Array)

          Psych.dump(value, line_width: -1).sub(/\A--- ?/, '').chomp
        end

        def inline(items)
          "[#{items.map { |item| scalar(item) }.join(', ')}]"
        end
      end
    end
  end
end
