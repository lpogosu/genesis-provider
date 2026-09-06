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
    # Ветка `else` читается тоже, но ровно в одном случае — см. #negated.
    #
    # Намёк принимается только тогда, когда захваченное имя — соседнее
    # свойство той же схемы. Эта единственная проверка отбрасывает
    # совпадения вида «minimum is 100» без всякого понимания предложения.
    class ConditionReader
      # Тройка ключевых слов «если — то — иначе» и источник, которым
      # помечается прочитанное ими условие.
      Keywords = Struct.new(:if_key, :then_key, :else_key, :origin)

      # Написания этой тройки в порядке доверия: сначала родная JSON Schema,
      # затем написание из реестра расширений OpenAPI для 3.0.
      IF_KEYWORDS = [
        Keywords.new('if', 'then', 'else', :if_then),
        Keywords.new('x-jsonschema-if', 'x-jsonschema-then', 'x-jsonschema-else',
                     :x_jsonschema_if)
      ].freeze
      DEPENDENT = 'dependentRequired'

      # @return [Array<Note>] о чём вызывающий должен предупредить
      attr_reader :notes

      # @param parent [Hash] схема, которой принадлежит поле
      # @param properties [Array<String>] имена её свойств
      # @param book [Rules::ConditionsBook] шаблоны для прозы
      # @param schema_path [String] JSONPath схемы, нужен для overlay
      # @param oas31 [Boolean] можно ли писать if/then нативно
      # @param formal [Hash{String => IR::RequiredWhen}] условия, прочитанные
      #   нормализацией из `discriminator` объединения
      def initialize(parent:, properties:, book:, schema_path:, oas31: false, formal: {})
        @parent = parent
        @properties = properties
        @book = book
        @schema_path = schema_path
        @oas31 = oas31
        @formal = formal
        @notes = []
      end

      # @param name [String] имя поля
      # @param node [Hash] схема этого поля
      # @return [IR::RequiredWhen, nil]
      def for(name, node)
        @formal[name] || dependent_required(name) || conditional(name) || hint(name, node)
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
        IF_KEYWORDS.each do |keys|
          found = positive(keys, name) || negated(keys, name)
          return found unless found.nil?

          note_negative(keys, name)
        end
        nil
      end

      def positive(keys, name)
        found = branch(keys.if_key, keys.then_key, name)
        return nil if found.nil?

        trigger, value = found
        evidence = Texts.t('analyzers.schema.condition.if_then',
                           keywords: "#{keys.if_key}/#{keys.then_key}",
                           condition: describe(trigger, value), field: name)
        condition(field: trigger, equals: value, origin: keys.origin, evidence: evidence)
      end

      # Отрицательная ветка читается как равенство, когда NegatedBranch
      # смог назвать оставшееся значение; источник и уверенность те же, что
      # у положительной ветки, потому что вывод структурный. Когда назвать
      # значение нельзя — предупреждение, см. #note_negative.
      def negated(keys, name)
        found = NegatedBranch.new(parent, keys, name)
        rest = found.value
        return nil if rest.nil?

        evidence = Texts.t('analyzers.schema.condition.negated_enum',
                           keywords: "#{keys.if_key}/#{keys.else_key}", trigger: found.trigger,
                           tested: found.tested, enum: found.listed,
                           condition: describe(found.trigger, rest), field: name)
        condition(field: found.trigger, equals: rest, origin: keys.origin, evidence: evidence)
      end

      # @return [Array(String, Object), nil] соседнее поле и значение, которое
      #   оно принимает
      def branch(if_key, then_key, name)
        test = parent[if_key]
        return nil unless test.is_a?(Hash)

        consequence = parent[then_key] || test['then']
        return nil unless required?(consequence, name)

        trigger_of(test)
      end

      # Отрицание, которое не свелось к равенству, нельзя выразить как
      # «обязательно, когда X равен Y», поэтому о нём сообщается, а не
      # молчится.
      def note_negative(keys, name)
        found = NegatedBranch.new(parent, keys, name)
        return unless found.declared?

        add_note(:conditional_required_hint, negative_message(keys, name, found),
                 severity: :warning)
      end

      def negative_message(keys, name, found)
        return off_enum_message(keys, name, found) if found.off_enum?

        Texts.t('analyzers.schema.condition.negative_branch', field: name,
                                                              keyword: keys.else_key)
      end

      def off_enum_message(keys, name, found)
        Texts.t('analyzers.schema.condition.negative_branch_off_enum',
                field: name, keyword: keys.else_key, trigger: found.trigger,
                tested: found.tested, enum: found.listed)
      end

      def required?(node, name)
        node.is_a?(Hash) && node['required'].is_a?(Array) && node['required'].include?(name)
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
