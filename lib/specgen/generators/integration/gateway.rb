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

        def currencies
          enum = conditions.find { |c| c.kind == :field_enum && precheck.role_of(c) == :currency }
          return inline(Array(enum.value.value)) if enum

          currency = profile.units&.currency
          return "#{inline([currency.value])}  # #{currency.evidence}" if currency&.known?

          "[]  # TODO: #{t('currencies_unknown')}"
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
