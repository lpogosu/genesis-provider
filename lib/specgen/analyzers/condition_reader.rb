# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Почему поле обязательно только иногда.
    #
    # Порядок здесь — порядок доверия из CLAUDE.md. `dependentRequired` и
    # `if/then` — формальная JSON Schema, они читаются как факт. OAS 3.0 эти
    # ключевые слова запрещает, поэтому зарегистрированные расширения
    # `x-jsonschema-if` и `x-jsonschema-then` читаются точно так же. И только
    # когда формально схема не говорит ничего, мы смотрим в описание — а
    # условие, вычитанное из прозы, это эвристика с низкой уверенностью,
    # предупреждением и готовым фрагментом overlay, но никогда не тихое
    # правило.
    #
    # Намёк принимается только тогда, когда захваченное имя — соседнее
    # свойство той же схемы. Эта единственная проверка отбрасывает
    # совпадения вида «minimum is 100» без всякого понимания предложения.
    class ConditionReader
      # Пары ключевых слов, выражающие «если это, то обязательно», в порядке
      # доверия: сначала родная JSON Schema, затем написание из реестра
      # расширений OpenAPI для 3.0.
      IF_KEYWORDS = [
        ['if', 'then', 'else', :if_then],
        ['x-jsonschema-if', 'x-jsonschema-then', 'x-jsonschema-else', :x_jsonschema_if]
      ].freeze
      DEPENDENT = 'dependentRequired'

      # @return [Array<Note>] о чём вызывающий должен предупредить
      attr_reader :notes

      # @param parent [Hash] схема, которой принадлежит поле
      # @param properties [Array<String>] имена её свойств
      # @param book [Rules::ConditionsBook] шаблоны для прозы
      # @param schema_path [String] JSONPath схемы, нужен для overlay
      # @param oas31 [Boolean] можно ли писать if/then нативно
      def initialize(parent:, properties:, book:, schema_path:, oas31: false)
        @parent = parent
        @properties = properties
        @book = book
        @schema_path = schema_path
        @oas31 = oas31
        @notes = []
      end

      # @param name [String] имя поля
      # @param node [Hash] схема этого поля
      # @return [IR::RequiredWhen, nil]
      def for(name, node)
        dependent_required(name) || conditional(name) || hint(name, node)
      end

      private

      attr_reader :parent, :book, :schema_path

      def dependent_required(name)
        listed = parent[DEPENDENT]
        return nil unless listed.is_a?(Hash)

        trigger, = listed.find { |_, required| Array(required).include?(name) }
        return nil if trigger.nil?

        condition(field: trigger.to_s, equals: nil, origin: :dependent_required,
                  evidence: Texts.t('analyzers.schema.condition.dependent_required',
                                    trigger: trigger, field: name))
      end

      def conditional(name)
        IF_KEYWORDS.each do |if_key, then_key, else_key, origin|
          found = branch(if_key, then_key, name)
          note_negative(if_key, else_key, name)
          next if found.nil?

          trigger, value = found
          return condition(field: trigger, equals: value, origin: origin,
                           evidence: if_then_evidence(if_key, then_key, trigger, value, name))
        end
        nil
      end

      def if_then_evidence(if_key, then_key, trigger, value, name)
        Texts.t('analyzers.schema.condition.if_then', keywords: "#{if_key}/#{then_key}",
                                                      condition: describe(trigger, value),
                                                      field: name)
      end

      # @return [Array(String, Object), nil] соседнее поле и значение, которое
      #   оно принимает
      def branch(if_key, then_key, name)
        test = parent[if_key]
        return nil unless test.is_a?(Hash)

        consequence = parent[then_key] || test['then']
        return nil unless consequence.is_a?(Hash) && required?(consequence, name)

        trigger_of(test)
      end

      # Отрицательную ветку нельзя выразить как «обязательно, когда X равен
      # Y», поэтому о ней сообщается, а не молчится.
      def note_negative(if_key, else_key, name)
        otherwise = parent[else_key] || (parent[if_key].is_a?(Hash) ? parent[if_key]['else'] : nil)
        return unless otherwise.is_a?(Hash) && required?(otherwise, name)

        add_note(:conditional_required_hint,
                 Texts.t('analyzers.schema.condition.negative_branch', field: name,
                                                                       keyword: else_key),
                 severity: :warning)
      end

      def required?(node, name)
        node['required'].is_a?(Array) && node['required'].include?(name)
      end

      # @return [Array(String, Object), nil]
      def trigger_of(test)
        properties = test['properties']
        return nil unless properties.is_a?(Hash)

        name, body = properties.find { |_, value| value.is_a?(Hash) }
        return nil if name.nil?

        [name.to_s, body.key?('const') ? body['const'] : body['enum']]
      end

      def hint(name, node)
        found = book.match(node['description'])
        return nil if found.nil?

        pattern, match = found
        trigger = match[:field]
        return nil unless sibling?(trigger, name)

        value = pattern.kind == 'equals' ? match[:value] : nil
        hinted(name, node, trigger, value, pattern)
      end

      # Захваченное имя обязано быть свойством той же схемы и не самим полем;
      # всё остальное — предложение, случайно похожее на правило.
      def sibling?(trigger, name)
        !trigger.nil? && trigger != name && @properties.include?(trigger)
      end

      def hinted(name, node, trigger, value, pattern)
        reads_as = describe(trigger, value)
        evidence = Texts.t('analyzers.schema.condition.description_hint',
                           pattern: pattern.name, condition: reads_as,
                           sentence: node['description'].to_s.strip.inspect)
        add_note(:conditional_required_hint,
                 Texts.t('analyzers.schema.condition.hint_warning', field: name,
                                                                    condition: reads_as),
                 suggested_overlay: overlay(name, trigger, value))
        condition(field: trigger, equals: value, origin: :description_hint, evidence: evidence,
                  confidence: book.hint_confidence)
      end

      def condition(field:, equals:, origin:, evidence:, confidence: nil)
        IR::RequiredWhen.new(field: field, equals: equals, origin: origin, evidence: evidence,
                             confidence: confidence)
      end

      def describe(trigger, value)
        return Texts.t('analyzers.schema.condition.presence', trigger: trigger) if value.nil?

        Texts.t('analyzers.schema.condition.equals', trigger: trigger,
                                                     value: Array(value).join(' | '))
      end

      # 3.1 принимает if/then нативно; 3.0 их запрещает и принимает вместо
      # них зарегистрированное расширение. Условие на наличие — это
      # dependentRequired в обеих версиях.
      def overlay(name, trigger, value)
        return presence_overlay(name, trigger) if value.nil?

        if_key, then_key = @oas31 ? %w[if then] : %w[x-jsonschema-if x-jsonschema-then]
        Texts.t('analyzers.schema.condition.overlay_equals', schema_path: schema_path,
                                                             if_key: if_key, then_key: then_key,
                                                             trigger: trigger, value: value,
                                                             field: name)
      end

      def presence_overlay(name, trigger)
        Texts.t('analyzers.schema.condition.overlay_presence', schema_path: schema_path,
                                                               keyword: DEPENDENT,
                                                               trigger: trigger, field: name)
      end

      def add_note(code, message, severity: :warning, suggested_overlay: nil)
        @notes << Note.new(code: code, message: message, json_path: schema_path,
                           severity: severity, suggested_overlay: suggested_overlay)
      end
    end
  end
end
