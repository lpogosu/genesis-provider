# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Реквизиты получателя отдельным методом с веткой по request_method.
      #
      # Здесь разбор условной обязательности наконец становится кодом, а не
      # комментарием. Спецификация говорит, что одно поле получателя
      # обязательно при одном значении типа, другое — при другом (примеры по
      # каждому провайдеру — в docs/STATUS.md); платформа держит реквизиты в
      # JSONB-хеше payout_requisite, ключ верхнего уровня в котором — это
      # payment_method шлюза, он же request_method (эксперты кейса,
      # 5 сентября 2026, вопросы 21 и 23). Значения enum роли recipient_type
      # становятся ветками, а поля раскладываются по ним по Field#required_when.
      #
      # Ветка появляется только там, где спецификация выразила условную
      # обязательность по значению этого enum: `case` с одинаковыми ветками
      # хуже, чем его отсутствие. Группа ищется на первом уровне вложенности
      # тела запроса (recipient, destination, remitter) — глубже реквизиты в
      # платёжных спецификациях не прячут, а угадывать вложенность, которой
      # платформа не подтвердила, запрещено.
      #
      # Роли, для которой в таблице requisites выражения нет, значение не
      # придумывается: поле получает TODO и строку «куда мапить» в
      # INTEGRATION.md (эксперты, вопрос 25: «не генерировать вслепую»).
      class Requisites
        # Роль поля, по значениям enum которого идёт ветвление.
        BRANCH_ROLE = :recipient_type
        # Суффикс имени метода: recipient → recipient_requisites.
        SUFFIX = '_requisites'
        # Меньше двух значений enum — ветвиться не по чему.
        MIN_BRANCHES = 2
        INDENT = 6
        # Записи хеша реквизитов встают в ту же колонку, что и поля
        # вложенного объекта в build_payload: комментарии считают ширину так же.
        ENTRY_DEPTH = 1

        # Одна ветка способа выплаты: значение enum спецификации, ключ
        # таблицы requisites (nil, если платформа такого способа не знает) и
        # поля, которые в эту ветку попадают.
        Branch = Struct.new(:value, :key, :fields, keyword_init: true)

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
          @found = detect
        end

        # @return [Boolean] ветка по request_method сгенерирована
        def branching?
          !@found.nil?
        end

        # @return [IR::Field, nil] поле-объект с реквизитами (recipient)
        def group
          @found&.first
        end

        # @return [IR::Field, nil] поле, по enum которого идёт ветвление
        def branch_field
          @found&.last
        end

        # @return [String, nil] имя приватного метода
        def method_name
          return nil unless branching?

          "#{Ruby.snake(group.name)}#{SUFFIX}"
        end

        # @return [String, nil] вызов метода для тела запроса
        def call
          return nil unless branching?

          "#{method_name}(operation, request_method)"
        end

        # @return [Array<Branch>] по ветке на значение enum, в порядке enum
        def branches
          return [] unless branching?

          @branches ||= branch_field.enum.map do |value|
            Branch.new(value: value, key: payment_method(value), fields: fields_for(value))
          end
        end

        # @param field [IR::Field]
        # @param branch [Branch]
        # @return [String, nil] выражение значения реквизита в этой ветке
        def expression(field, branch)
          return Ruby.literal(branch.value) if field.equal?(branch_field)
          return nil unless field.role.known?

          role = field.role.value
          @ctx.requisites.expression(branch.key.to_s, role) || @ctx.accessor(role) ||
            @ctx.currency_constant_for(role)
        end

        # Покрыто ли поле сгенерированным кодом: хоть одна ветка даёт ему
        # выражение. Спрашивает измерение покрытия в report.md.
        # @param field [IR::Field]
        # @return [Boolean]
        def covers?(field)
          branches.any? do |branch|
            branch.fields.any? { |item| item.equal?(field) } && !expression(field, branch).nil?
          end
        end

        # Поля группы, для которых выражения нет ни в одной ветке: их и
        # перечисляет таблица «куда мапить» в INTEGRATION.md.
        # @return [Array<Array(IR::Field, Branch)>]
        def gaps
          branches.flat_map do |branch|
            branch.fields.reject { |field| expression(field, branch) }
                  .map { |field| [field, branch] }
          end
        end

        # @return [Method, nil]
        def method
          return nil unless branching?

          Method.new(name: method_name, params: [{ name: 'operation' },
                                                 { name: 'request_method' }],
                     doc: doc, body: body)
        end

        private

        # Группа реквизитов: поле-объект первого уровня, внутри которого есть
        # поле роли recipient_type с enum хотя бы из двух значений и хотя бы
        # одно поле, обязательное при одном из этих значений.
        def detect
          schema = @ctx.schema(@ctx.create_operation&.request_schema)
          return nil if schema.nil?

          schema.fields.each do |field|
            nested = nested_schema(field)
            next if nested.nil?

            type_field = type_field_of(nested)
            return [field, nested, type_field] if type_field && conditional?(nested, type_field)
          end
          nil
        end

        def nested_schema(field)
          return nil if field.type == 'array' || field.schema.nil?

          @ctx.schema(field.schema)
        end

        def type_field_of(schema)
          schema.fields.find do |field|
            field.role.value == BRANCH_ROLE && field.enum && field.enum.size >= MIN_BRANCHES
          end
        end

        # Условная обязательность по значению того самого enum — то, ради
        # чего ветка и появляется.
        def conditional?(schema, type_field)
          schema.fields.any? { |field| branch_values(field, type_field).any? }
        end

        # @return [Array<String>] значения enum, при которых поле обязательно
        def branch_values(field, type_field)
          rule = field.required_when
          return [] if rule.nil? || rule.field != type_field.name

          rule.values.map(&:to_s)
        end

        def group_schema
          @found[1]
        end

        # Поле без условия — общее для всех веток: спецификация требует его
        # всегда. Поле с условием на другое поле (dependentRequired на
        # соседа) тоже общее: его условие ветку не выбирает.
        def fields_for(value)
          group_schema.fields.select do |field|
            values = branch_values(field, branch_field)
            values.empty? || values.include?(value.to_s)
          end
        end

        # Способ выплаты платформы для значения enum: по нормализованному
        # имени. Совпадения нет — ключа платформы не существует, и это
        # видно в ветке (TODO вместо выражений).
        def payment_method(value)
          name = Rules::Normalizer.call(value)
          @ctx.requisites.payment_methods.find { |key| Rules::Normalizer.call(key) == name }
        end

        def doc
          Ruby.comment(@ctx.t('requisites_doc', field: group.name,
                                                hash: @ctx.requisites.hash_expression.to_s),
                       width: Ruby::WIDTH - 4) +
            ['# @param operation [Object]', '# @param request_method [Object]',
             "# @return [Hash] #{@ctx.t('requisites_returns')}"]
        end

        def body
          lines = ['case request_method']
          branches.each do |branch|
            lines << "when #{Ruby.str(branch.key || branch.value)}"
            lines.concat(Ruby.indent(branch_lines(branch), 2))
          end
          lines + ['else', *Ruby.indent(else_lines, 2), 'end']
        end

        def branch_lines(branch)
          entries = branch.fields.filter_map do |field|
            @ctx.parts_payload.entry_for(field, expression(field, branch), ENTRY_DEPTH)
          end
          lines = @ctx.parts_payload.render(entries)
          return unknown_method_lines(branch) + ['{}'] if lines.empty?

          unknown_method_lines(branch) + ['{', *Ruby.indent(lines, 2), '}']
        end

        # Ветка, для которой платформа способа выплаты не знает: значение
        # enum спецификации взято как есть, а сверить его с payment_method
        # шлюза должен человек.
        def unknown_method_lines(branch)
          return [] if branch.key

          todo(@ctx.t('requisites_method_unknown', value: branch.value,
                                                   hash: @ctx.requisites.hash_expression.to_s))
        end

        def else_lines
          todo(@ctx.t('requisites_else', values: branches.map(&:value).join(', '))) + ['{}']
        end

        def todo(text)
          Ruby.comment(text, width: Ruby::WIDTH - INDENT - 2, prefix: '# TODO: ')
        end
      end
    end
  end
end
