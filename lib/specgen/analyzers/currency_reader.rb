# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Код валюты суммы: откуда он известен и насколько ему верить.
    #
    # Порядок — порядок доверия. Расширение overlay на поле суммы побеждает
    # всё. Затем поле-сосед суммы, чьё имя — точный синоним роли currency:
    # `const` или `enum` из одного значения читаются как факт, `default` и
    # `example` — как эвристика с убывающей уверенностью, потому что пример
    # показывает одну из возможных валют, а не единственную. Затем такое же
    # поле в любой другой схеме: ответ провайдера тоже называет валюту.
    #
    # Enum из нескольких валют кодом не является. Он возвращается списком,
    # чтобы анализатор мог сверить экспоненты по ISO 4217 и предупредить, а
    # не взять первую валюту как единственную.
    class CurrencyReader
      # Что удалось узнать.
      #
      #   derived    Derived<String>: код ISO 4217, либо не выведено
      #   codes      значения enum, когда валют несколько (иначе [код] или [])
      #   name       имя поля валюты или nil
      #   json_path  JSONPath поля валюты или nil
      Result = Struct.new(:derived, :codes, :name, :json_path, keyword_init: true)

      EXTENSION = 'x-specgen-currency'
      ROLE = :currency
      # Ключевое слово, уверенность и ключ обоснования для подсказок, которые
      # называют одну из возможных валют, а не единственную.
      HINTS = [['default', 0.7, 'currency_default'], ['example', 0.6, 'currency_example']].freeze

      # @param index [SchemaIndex]
      # @param lookup [RoleLookup]
      # @param entry [SchemaIndex::Entry] схема, в которой лежит сумма
      # @param node [Hash] узел поля суммы
      def initialize(index:, lookup:, entry:, node:)
        @index = index
        @lookup = lookup
        @entry = entry
        @node = node
        @silent = nil
      end

      # @return [Result]
      def call
        overlay || sibling || elsewhere || none
      end

      private

      def overlay
        value = @node[EXTENSION]
        return nil unless value.is_a?(String) && !value.strip.empty?

        code = value.strip.upcase
        result(IR::Derived.overlay(code, evidence: t('currency_overlay', value: code)), [code])
      end

      def sibling
        @index.fields(@entry).each do |name, node, path|
          found = read(name, node, path)
          return found if found
        end
        nil
      end

      def elsewhere
        @index.each_field do |entry, name, node, path|
          next if entry.equal?(@entry)

          found = read(name, node, path)
          return found if found
        end
        nil
      end

      # @return [Result, nil] nil, если поле не про валюту или ничего о ней
      #   не говорит
      def read(name, node, path)
        return nil unless @lookup.role?(name, ROLE)

        codes = listed(node)
        keyword = node.key?('const') ? 'const' : 'enum'
        return single(codes.first, name, path, keyword) if codes.size == 1
        return multiple(codes, name, path) if codes.size > 1

        hinted(node, name, path) || remember_silent(name, path)
      end

      def listed(node)
        return [node['const']].grep(String).map { |code| code.strip.upcase } if node.key?('const')

        enum = node['enum']
        enum.is_a?(Array) ? enum.grep(String).map { |code| code.strip.upcase }.uniq : []
      end

      def single(code, name, path, keyword)
        evidence = t('currency_listed', keyword: keyword, value: code, name: name)
        result(IR::Derived.structural(code, evidence: evidence), [code], name, path)
      end

      def multiple(codes, name, path)
        evidence = t('currency_multiple', name: name, values: codes.join(', '))
        result(IR::Derived.unknown(evidence: evidence), codes, name, path)
      end

      def hinted(node, name, path)
        HINTS.each do |keyword, confidence, key|
          value = node[keyword]
          next unless value.is_a?(String) && !value.strip.empty?

          code = value.strip.upcase
          derived = IR::Derived.heuristic(code, confidence: confidence,
                                                evidence: t(key, value: code, name: name))
          return result(derived, [code], name, path)
        end
        nil
      end

      # Поле валюты есть, но молчит: об этом скажет обоснование, если больше
      # никто ничего не скажет.
      def remember_silent(name, path)
        @silent ||= [name, path]
        nil
      end

      def none
        return result(IR::Derived.unknown(evidence: t('currency_missing')), []) if @silent.nil?

        name, path = @silent
        result(IR::Derived.unknown(evidence: t('currency_silent', name: name)), [], name, path)
      end

      def result(derived, codes, name = nil, path = nil)
        Result.new(derived: derived, codes: codes, name: name, json_path: path)
      end

      def t(key, **params)
        Texts.t("analyzers.units.#{key}", **params)
      end
    end
  end
end
