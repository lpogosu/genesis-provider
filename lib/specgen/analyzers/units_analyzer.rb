# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.units: в каких единицах провайдер ждёт сумму и какой
    # множитель применить к `operation.amount`.
    #
    # Порядок вывода — порядок из CLAUDE.md, и он же порядок доверия:
    # расширения overlay на поле суммы (`x-specgen-amount-unit`,
    # `x-specgen-exponent`, `x-specgen-currency`) побеждают всё; затем
    # `type: integer` вместе с кодом валюты даёт минорные единицы с
    # экспонентой из ISO 4217 (rules/currencies.yml); `type: number` с
    # дробным примером — мажорные; после чего вывод сверяется с `minimum` и
    # описанием, и расхождение становится предупреждением, а не молчанием.
    # Слово «копейках» — только подтверждающий сигнал: множитель определяет
    # стандарт по коду валюты, а не проза.
    #
    # Поле суммы находится точным словарным поиском по синонимам роли
    # amount, сначала в телах запросов — это то, что сервис отправляет, —
    # затем везде. Роль самому полю здесь не проставляется: это работа
    # матчеров. Без поля суммы профиль получает `units = nil` и
    # предупреждение: без множителя сервис не соберёт запрос.
    class UnitsAnalyzer < Base
      EXTENSION = 'x-specgen-exponent'
      ROLE = :amount
      # Код валюты, которого нет в таблице ISO 4217, получает экспоненту по
      # умолчанию из справочника — но с уверенностью, которая не пройдёт ни
      # один порог без подтверждения человеком.
      DEFAULT_EXPONENT_CONFIDENCE = 0.5
      # Значения для заготовки overlay, когда своих вывести не удалось.
      PLACEHOLDER = { unit: :minor, exponent: 2 }.freeze

      # Заполняет `profile.units`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @index = SchemaIndex.new(data)
        @lookup = RoleLookup.new(rules, data)
        found = locate
        return no_amount if found.nil?

        @entry, @name, @node, @path = found
        profile.units = build
        profile
      end

      private

      # @return [Array(SchemaIndex::Entry, String, Hash, String), nil]
      def locate
        requests, others = @index.entries.partition { |entry| @index.request?(entry) }
        (requests + others).each do |entry|
          @index.fields(entry).each do |name, node, path|
            return [entry, name, node, path] if @lookup.role?(name, ROLE)
          end
        end
        nil
      end

      # Единица и экспонента не могут быть увереннее ролей полей, по которым
      # выведены: поле суммы, опознанное матчерами с уверенностью 0.43,
      # ровно настолько же обосновывает множитель (RoleLookup#temper).
      def build
        currency = CurrencyReader.new(index: @index, lookup: @lookup, entry: @entry,
                                      node: @node, book: rules.currencies).call
        exponent = overlay_exponent || @lookup.temper(exponent_for(currency), currency.name)
        unit = @lookup.temper(unit_for(exponent, currency), @name)
        IR::Units.new(currency: currency.derived, unit: unit, exponent: exponent,
                      json_path: @path)
      end

      def overlay_exponent
        value = @node[EXTENSION]
        return nil unless value.is_a?(Integer) && value >= 0

        IR::Derived.overlay(value, evidence: t('exponent_overlay', value: value))
      end

      def exponent_for(currency)
        return known_exponent(currency.derived.value) if currency.derived.known?
        return shared_exponent(currency) if currency.codes.size > 1

        warn_currency(t('currency_missing_message', evidence: currency.derived.evidence))
        IR::Derived.unknown(evidence: t('exponent_unknown'))
      end

      def known_exponent(code)
        exponent = rules.currencies.exponent(code)
        return registry(exponent, 'exponent_iso', code: code, exponent: exponent) if exponent

        fallback = rules.currencies.default_exponent
        warn_currency(t('currency_code_message', code: code, exponent: fallback))
        registry(fallback, 'exponent_default', code: code, exponent: fallback,
                                               confidence: DEFAULT_EXPONENT_CONFIDENCE)
      end

      # Несколько валют с одной экспонентой — множитель всё же известен; с
      # разными — нет, и человек решает.
      def shared_exponent(currency)
        listed = currency.codes.join(', ')
        exponents = currency.codes.map { |code| rules.currencies.exponent(code) }.uniq
        shared = exponents.size == 1 ? exponents.first : nil
        warn_currency(t('currency_multiple_message', name: currency.name, values: listed),
                      severity: shared ? :info : :warning)
        return IR::Derived.unknown(evidence: t('exponent_differs', codes: listed)) if shared.nil?

        registry(shared, 'exponent_shared', codes: listed, exponent: shared)
      end

      def registry(value, key, confidence: IR::Derived::REGISTRY_CONFIDENCE, **params)
        IR::Derived.registry(value, confidence: confidence, evidence: t(key, **params))
      end

      def warn_currency(message, severity: :warning)
        fragment = t('currency_overlay_fragment', path: @path)
        profile.warn(:currency_unknown, message, json_path: @path, severity: severity,
                                                 suggested_overlay: fragment)
      end

      def unit_for(exponent, currency)
        result = UnitReader.new(node: @node, name: @name, book: rules.currencies,
                                exponent: exponent, code: currency.derived.value).call
        result.notes.each do |code, message|
          profile.warn(code, message, json_path: @path,
                                      suggested_overlay: units_overlay(result.derived, exponent))
        end
        result.derived
      end

      def units_overlay(unit, exponent)
        t('overlay_fragment', path: @path,
                              unit: unit.known? ? unit.value : PLACEHOLDER[:unit],
                              exponent: exponent.known? ? exponent.value : PLACEHOLDER[:exponent])
      end

      def no_amount
        profile.units = nil
        profile.warn(:units_unknown, t('missing_amount_message'),
                     json_path: json_path('components', 'schemas'))
        profile
      end

      def t(key, **params)
        Texts.t("analyzers.units.#{key}", **params)
      end
    end
  end
end
