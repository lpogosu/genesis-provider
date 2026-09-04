# frozen_string_literal: true

module SpecGen
  module Rules
    # Проверки, которые нужны каждому справочнику: значение вне закрытого
    # набора, непустая строка, целое число в диапазоне, список строк,
    # компилируемый шаблон. Каждая записывает проблему и возвращает nil (или
    # пустой список), а не поднимает ошибку, — так одна загрузка сообщает обо
    # всех промахах во всех файлах, а не останавливается на первом.
    #
    # Подмешивается в Book, который даёт #complain.
    #
    # Сообщение собирается из шаблона локали и названия проверяемого элемента
    # (%{what}), которое приходит из того же слоя: одна проверка обслуживает
    # все справочники, а язык сообщения меняется без правки кода.
    module Checks
      # @param value [Object] значение, как написано в справочнике
      # @param allowed [Array<Symbol>] закрытый набор
      # @param what [String] название элемента для сообщения
      # @param at [String] JSONPath значения
      # @return [Symbol, nil]
      def symbol_in(value, allowed, what, at)
        symbol = value.is_a?(String) ? value.to_sym : value
        return symbol if allowed.include?(symbol)

        fault('checks.unknown_value', at, what: what, value: value.inspect,
                                          allowed: allowed.join(', '))
        nil
      end

      # @param what [String] название элемента для сообщения
      # @param at [String] JSONPath значения
      # @return [String, nil]
      def text(value, what, at)
        return value if value.is_a?(String) && !value.strip.empty?

        fault('checks.text', at, what: what, got: describe(value))
        nil
      end

      # @param range [Range, nil] допустимые значения, nil — любое целое
      # @return [Integer, nil]
      def integer(value, what, at, range: nil)
        unless value.is_a?(Integer)
          fault('checks.integer', at, what: what, got: describe(value))
          return nil
        end
        return value if range.nil? || range.cover?(value)

        fault('checks.range', at, what: what, range: range, got: value)
        nil
      end

      # @param required [Boolean] считать ли отсутствие списка проблемой
      # @return [Array<String>] прошедшие проверку элементы; пустой список,
      #   если сам список негоден
      def string_list(value, what, at, required: true)
        return [] if value.nil? && !required

        unless value.is_a?(Array) && !value.empty?
          fault('checks.list', at, what: what, got: describe(value))
          return []
        end

        value.each_with_index.filter_map do |item, index|
          text(item, noun(:entry, what: what), "#{at}[#{index}]")
        end
      end

      # @return [Regexp, nil]
      def pattern(value, what, at)
        source = text(value, what, at)
        return nil if source.nil?

        Regexp.new(source)
      rescue RegexpError => e
        fault('checks.bad_pattern', at, what: what, error: e.message)
        nil
      end

      # @param required [Boolean] считать ли отсутствие объекта проблемой
      # @return [Hash] сам объект или пустой, с записанной проблемой
      def mapping(value, what, at, required: true)
        return value if value.is_a?(Hash)
        return {} if value.nil? && !required

        fault('checks.mapping', at, what: what, got: describe(value))
        {}
      end

      # @return [String] значение так, как его читает автор справочника
      def describe(value)
        return Texts.t('rules.checks.nothing') if value.nil?

        "#{SpecLoader::TypeName.of(value)} #{value.inspect}"
      end

      # Записывает проблему по ключу локали внутри `rules.`.
      # @param key [String] ключ без префикса, например "checks.text"
      # @param at [String, nil] JSONPath элемента
      # @param params [Hash{Symbol => Object}] подстановки шаблона
      # @return [nil]
      def fault(key, at, **params)
        complain(Texts.t("rules.#{key}", **params), at)
      end

      # @param key [Symbol] ключ под `rules.noun.`
      # @param params [Hash{Symbol => Object}] подстановки шаблона
      # @return [String] название проверяемого элемента для сообщения
      def noun(key, **params)
        Texts.t("rules.noun.#{key}", **params)
      end
    end
  end
end
