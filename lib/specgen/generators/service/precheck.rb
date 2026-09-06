# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Метод предпроверок: super, ранний выход, затем условия из
      # profile.conditions, пересчитанные во внутренние единицы через
      # profile.units. `minimum: 100000` при экспоненте 2 становится
      # проверкой `operation.amount < 1000`, а в комментарии остаются обе
      # величины.
      class Precheck
        # Виды условий, которые проверяются до запроса. Ограничение отмены
        # уходит в метод отмены, пауза и ключ идемпотентности — в таблицы.
        CHECKED = %i[min_amount max_amount field_max_length field_pattern field_enum].freeze
        AMOUNT_KINDS = %i[min_amount max_amount].freeze
        # Отступ тела метода в классе.
        INDENT = 6
        # Предикат успешного результата, если контракт его не назвал.
        DEFAULT_PREDICATE = 'success?'
        # Список enum длиннее этого выносится в локальную переменную.
        INLINE_LIST = 40

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @spec = ctx.contract.method_names.map { |name| ctx.contract.method_spec(name) }
                     .find { |spec| spec.roles.empty? }
        end

        # @return [Method, nil] nil, если контракт не описывает предпроверку
        def method
          return nil if @spec.nil?

          Method.new(name: @spec.name, params: @spec.params, doc: doc, body: body)
        end

        # Два поля с одной ролью и одинаковым ограничением (у PayPal
        # `sender_batch_id` и `sender_item_id` — оба external_id) дают две
        # побайтово одинаковые проверки: выражение берётся по роли, а не по
        # имени поля. Повтор убирается по тройке «вид, роль, значение» —
        # разные границы у одной роли остаются обе, их пересечение и есть
        # ограничение провайдера.
        # @return [Array<IR::Condition>] условия, проверяемые до запроса
        def conditions
          create = @ctx.create_operation
          selected = @ctx.profile.conditions.select do |condition|
            CHECKED.include?(condition.kind) && !constant?(condition) &&
              (condition.operation.nil? || condition.operation == create&.key)
          end
          selected.uniq { |condition| [condition.kind, role_of(condition), condition.value.value] }
        end

        # Условие, которое проверять нечем и незачем: значение поля в теле
        # запроса задано по построению. Валюту сервис берёт из спецификации
        # константой (поля currency у операции нет), а способ выплаты
        # печатается литералом из enum в своей ветке реквизитов — сравнение
        # в обоих случаях всегда истинно, а лишний guard читается как
        # настоящая проверка.
        # @param condition [IR::Condition]
        # @return [Boolean]
        def constant?(condition)
          role = role_of(condition)
          return true unless @ctx.currency_constant_for(role).nil?

          role == Requisites::BRANCH_ROLE && @ctx.parts_requisites.branching?
        end

        # Условие словами, как в комментарии над проверкой: «minimum: 100000
        # в единицах провайдера = 1000.00 RUB в мажорных (задано явно 1.00)».
        # INTEGRATION.md печатает ту же фразу, что и код.
        # @param condition [IR::Condition]
        # @return [String]
        def description(condition)
          derived = condition.value
          major = major_text(condition)
          @ctx.t("condition.#{kind_of(condition, major)}",
                 field: condition.field, value: Reporter::Format.constraint(derived.value),
                 major: major, source: @ctx.source_label(derived))
        end

        # Без множителя границы в мажорных единицах нет, и фраза
        # «= в мажорных» с пустым местом обещает пересчёт, которого не было.
        def kind_of(condition, major)
          kind = condition.kind
          return kind unless major.empty? && AMOUNT_KINDS.include?(kind)

          :"#{kind}_raw"
        end

        # "1000.00 RUB" для границ суммы; пустая строка для остальных.
        # @param condition [IR::Condition]
        # @return [String]
        def major_text(condition)
          units = @ctx.profile.units
          raw = condition.value.value
          amount = AMOUNT_KINDS.include?(condition.kind) && raw.is_a?(Numeric)
          return '' unless amount && units&.known?

          digits = units.exponent.known? ? units.exponent.value : 0
          "#{format("%.#{digits}f", Rational(raw, units.multiplier))} #{units.currency.value}"
        end

        # Граница суммы во внутренних (мажорных) единицах: сырое значение
        # спецификации, делённое на множитель ISO 4217; без множителя —
        # вызов пересчёта в коде.
        # @param raw [Object]
        # @return [String] литерал Ruby
        def amount(raw)
          multiplier = @ctx.profile.units&.multiplier
          # Разделители разрядов нужны и здесь: Style/NumericLiterals читает
          # и аргумент пересчёта (у GOV.UK Pay maximum — 10000000 пенсов).
          return "to_provider_units(#{literal(raw)})" if multiplier.nil? || !raw.is_a?(Numeric)

          major = Rational(raw, multiplier)
          Ruby.number(major.denominator == 1 ? major.to_i : major.to_f)
        end

        # @return [String] литерал Ruby для сырого значения спецификации
        def literal(raw)
          raw.is_a?(Numeric) ? Ruby.number(raw) : raw.to_s
        end

        # Роль поля условия: по схеме тела запроса операции создания, иначе по
        # любой схеме, где такое поле есть.
        # @param condition [IR::Condition]
        # @return [Symbol, nil]
        def role_of(condition)
          return :amount if AMOUNT_KINDS.include?(condition.kind)

          request = @ctx.schema(@ctx.create_operation&.request_schema)
          [request, *@ctx.profile.schemas.values].compact.each do |schema|
            field = schema.field(condition.field)
            return field.role.value if field&.role&.known?
          end
          nil
        end

        # Поле реквизитов: его значение зависит от способа выплаты, поэтому
        # одной проверкой в check_conditions его не покрыть. Отчёт объясняет
        # этот пробел теми же словами, что и TODO в коде.
        # @param condition [IR::Condition]
        # @return [Boolean]
        def in_requisites?(condition)
          requisites = @ctx.parts_requisites
          requisites.branching? && requisites.branches.any? do |branch|
            branch.fields.any? { |field| field.name == condition.field }
          end
        end

        # @param condition [IR::Condition]
        # @return [String, nil] код отказа, который даёт проверка; nil, если
        #   у платформы нет выражения для поля и проверка осталась TODO
        def failure_code(condition)
          role = role_of(condition)
          return nil if @ctx.accessor(role).nil?

          "#{role}_#{suffix(condition.kind)}"
        end

        private

        def doc
          Ruby.comment(@spec.purpose.to_s, width: Ruby::WIDTH - 4) +
            @spec.params.map { |param| "# @param #{param[:name]} [Object]" } +
            ["# @return [Object] #{@spec.returns}"]
        end

        def body
          lines = super_lines
          conditions.each { |condition| lines.concat(check(condition)) }
          lines << @ctx.success
        end

        def super_lines
          return [] unless @spec.calls_super?

          predicate = @ctx.platform.success_predicate || DEFAULT_PREDICATE
          ['result = super', "return result unless result.#{predicate}", '']
        end

        def check(condition)
          role = role_of(condition)
          accessor = @ctx.accessor(role)
          lines = comments(condition)
          return lines + todo(condition) if accessor.nil?

          setup, expression, negate = predicate(condition, role, accessor)
          failure = @ctx.validation_failure(failure_code(condition))
          lines + setup + Ruby.guard(failure, expression, indent: INDENT, negate: negate)
        end

        def suffix(kind)
          { min_amount: 'below_minimum', max_amount: 'above_maximum', field_max_length: 'too_long',
            field_pattern: 'invalid_format', field_enum: 'not_allowed' }.fetch(kind)
        end

        # @return [Array(Array<String>, String, Boolean)] подготовительные
        #   строки, условие, unless вместо if
        def predicate(condition, role, accessor)
          value = condition.value.value
          case condition.kind
          when :min_amount then [[], "#{accessor} < #{amount(value)}", false]
          when :max_amount then [[], "#{accessor} > #{amount(value)}", false]
          when :field_max_length then [[], "#{accessor}.to_s.length > #{Ruby.number(value)}", false]
          when :field_pattern then [[], "#{accessor}.to_s.match?(#{Ruby.regexp(value)})", true]
          else enum_predicate(role, accessor, Array(value).map(&:to_s))
          end
        end

        # Длинный список допустимых значений уходит в локальную переменную,
        # чтобы guard-строка оставалась в ширине.
        def enum_predicate(role, accessor, values)
          literal = Ruby.array(values)
          return [[], "#{literal}.include?(#{accessor})", true] if literal.size <= INLINE_LIST

          name = "allowed_#{role}"
          prefix = "#{name} = "
          lines = Ruby.words(values, width: Ruby::WIDTH - INDENT - prefix.size)
          pad = ' ' * prefix.size
          setup = lines.each_with_index.map { |line, i| (i.zero? ? prefix : pad) + line }
          [setup, "#{name}.include?(#{accessor})", true]
        end

        def comments(condition)
          lines = comment(description(condition))
          lines.concat(comment(@ctx.t('condition_doubt'))) if @ctx.doubtful?(condition.value)
          lines
        end

        # Поле реквизитов проверить одной строкой нельзя: его значение
        # зависит от способа выплаты и собирается в своей ветке. Ограничение
        # спецификации от этого не пропадает — оно в INTEGRATION.md и в
        # чек-листе report.md, но выдавать проверку одной ветки за проверку
        # всех было бы хуже её отсутствия.
        def todo(condition)
          key, params = if in_requisites?(condition)
                          ['condition_in_requisites',
                           { method: @ctx.parts_requisites.method_name }]
                        else
                          ['condition_no_accessor', {}]
                        end
          comment(@ctx.t(key, field: condition.field, **params), prefix: '# TODO: ')
        end

        def comment(text, prefix: '# ')
          Ruby.comment(text, width: Ruby::WIDTH - INDENT, prefix: prefix)
        end
      end
    end
  end
end
