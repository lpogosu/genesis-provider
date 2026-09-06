# frozen_string_literal: true

module SpecGen
  module Validators
    # Объект операции платформы, собранный так, чтобы сгенерированный сервис
    # прочитал из него ровно то, что записано в фикстуре запроса.
    #
    # Это обратный ход генерации: шаблон печатал выражения платформы по ролям
    # полей, а здесь по тем же ролям раскладываются значения примера. Поэтому
    # совпадение тела запроса с фикстурой — не тавтология: значения проходят
    # через выражения контракта, пересчёт суммы и ветку по способу выплаты.
    #
    # Поля объекта — только те, что назвал rules/contract.yml. Обращение к
    # полю, которого платформа не гарантирует, поднимает NoMethodError, и
    # прогон превращает его в находку: молча вернуть nil значило бы скрыть
    # ровно ту ошибку, ради которой прогон и заведён.
    class Payment
      # Поля, которых нет в выражениях контракта, но которые платформа
      # называет гарантированными (эксперты кейса, 5 сентября 2026).
      EXTRA_FIELDS = %w[gateway].freeze
      # Сумма, когда пример спецификации не дал ни одного числа.
      DEFAULT_AMOUNT = 1
      # Значение request_method, когда способа выплаты в спецификации нет.
      QUOTES = /\A['"](.*)['"]\z/

      # @param ctx [Generators::Service::Context]
      # @param parts [Hash{Symbol => Object}] презентеры сервиса
      # @param fixtures [FixtureSet]
      def initialize(ctx:, parts:, fixtures:)
        @ctx = ctx
        @parts = parts
        @fixtures = fixtures
      end

      # @return [Struct] объект операции для вызова методов сервиса
      def operation
        @operation ||= struct.new(**values)
      end

      # @return [String] имя, под которым выражения контракта читают операцию
      def root
        @root ||= roots.first || 'operation'
      end

      # Способ выплаты, с которым собрана фикстура запроса: ключ ветки
      # реквизитов, иначе значение по умолчанию из контракта.
      # @return [String]
      def request_method
        branch = current_branch
        return (branch.key || branch.value).to_s if branch

        spec = @ctx.contract.method_for(:create_payout) ||
               @ctx.contract.method_for(:create_deposit)
        default = spec&.params&.last
        default.to_h[:default].to_s[QUOTES, 1] || 'create'
      end

      # @return [Hash] тело фикстуры запроса операции создания
      def request_body
        create = @ctx.create_operation
        fixture = create && @fixtures.request(create.key)
        body = fixture && fixture['body']
        body.is_a?(Hash) ? body : {}
      end

      # Ключ идемпотентности, который сервис обязан посчитать от operation.id:
      # тот же UUID v5 (RFC 4122 §4.3) от того же имени. Считается здесь, а не
      # берётся из заголовка фикстуры, потому что проверяется детерминизм
      # ключа, а не совпадение двух записей одного примера.
      # @return [String]
      def idempotency_key
        reference = external_id.to_s
        return reference if @ctx.profile.idempotency&.strategy&.value == :external_id

        Generators::Uuid.v5(@ctx.rules.idempotency.namespace, "#{@ctx.naming.slug}:#{reference}")
      end

      # Идентификатор операции у провайдера — тот, который сервис прочитает
      # из ответа на создание и вернёт платформе как result[:id].
      # @return [Object, nil]
      def provider_key
        create = @ctx.create_operation
        response = create&.success_responses&.first
        path = response && @ctx.role_path(response.schema, :provider_operation_id)
        fixture = create && @fixtures.success_response(create.key, success_codes(create))
        Generators::Fixtures::Values.dig_path(fixture && fixture['body'], path)
      end

      private

      # Имена полей операции: из выражений доступа контракта плюс хеш
      # реквизитов, который выражения читают отдельно.
      def fields
        @fields ||= (accessors.values.map(&:last) + [requisite_field] + EXTRA_FIELDS).compact.uniq
      end

      def struct
        Struct.new(*fields.map(&:to_sym), keyword_init: true)
      end

      def values
        table = accessors.to_h { |role, (_root, name)| [name.to_sym, value_for(role)] }
        table[requisite_field.to_sym] = requisites_hash if requisite_field
        EXTRA_FIELDS.each { |name| table[name.to_sym] ||= @ctx.naming.slug }
        table
      end

      # @return [Hash{Symbol => Array(String, String)}] роль → приёмник и поле
      def accessors
        @accessors ||= @ctx.platform.roles(:accessors).to_h do |role|
          [role, Expression.attribute(@ctx.accessor(role))]
        end.compact
      end

      def roots
        accessors.values.map(&:first).uniq
      end

      def requisite_field
        @requisite_field ||= Expression.attribute(@ctx.requisites.hash_expression)&.last
      end

      def value_for(role)
        case role
        when :amount then major_amount
        when :provider_operation_id then provider_key
        when :status then status_value
        when :external_id then external_id
        else body_value(role)
        end
      end

      # Идентификатор операции платформы: та же цепочка, которой генератор
      # фикстур считал ключ идемпотентности — значение из примера запроса,
      # иначе пример роли из любой схемы, иначе заглушка.
      def external_id
        body_value(:external_id) || Generators::Fixtures::Requests::OPERATION_PLACEHOLDER
      end

      # Сумма платформы в мажорных единицах: значение примера, делённое на
      # тот же множитель ISO 4217, на который сервис его умножит обратно.
      def major_amount
        number = numeric(body_value(:amount))
        multiplier = @ctx.profile.units&.multiplier
        return number if multiplier.nil?

        major = Rational(number, multiplier)
        major.denominator == 1 ? major.to_i : major.to_f
      end

      # operation.amount у платформы — число всегда, даже когда пример
      # спецификации написал сумму строкой ("100.00"). Подставлять строку
      # значило бы проверять класс на входе, которого у него не бывает.
      def numeric(raw)
        return raw if raw.is_a?(Numeric)

        text = raw.to_s
        Integer(text, exception: false) || Float(text, exception: false) || DEFAULT_AMOUNT
      end

      def success_codes(operation)
        @parts[:http].success_codes(operation)
      end

      # Статус, при котором разрешена отмена: иначе метод отмены откажет
      # раньше, чем дойдёт до клиента, и проверять будет нечего.
      def status_value
        @parts[:extras].cancellable_statuses&.first || @ctx.contract.internal_statuses.first
      end

      # Значение роли из примера запроса, а если такого поля в теле нет — из
      # примера любой схемы профиля, как это делает генератор фикстур.
      #
      # Ищутся все поля роли, а не первое: сгенерированный payload кладёт
      # выражение платформы в каждое поле этой роли, а пример спецификации
      # заполняет не обязательно первое из них. Возьми мы первое, значение
      # операции разошлось бы с телом фикстуры на ровном месте.
      def body_value(role)
        found = role_paths(@ctx.create_operation&.request_schema, role)
                .filter_map { |path| Generators::Fixtures::Values.dig_path(request_body, path) }
        found.first || examples.role_example(role)
      end

      # @return [Array<Array<String>>] пути всех полей роли в схеме
      def role_paths(name, role, prefix = [], visited = [])
        schema = @ctx.schema(name)
        return [] if schema.nil? || visited.include?(name)

        schema.fields.flat_map do |field|
          at = [*prefix, field.name]
          own = field.role.value == role ? [at] : []
          own + role_paths(field.schema, role, at, [*visited, name])
        end
      end

      def examples
        @examples ||= Generators::Fixtures::Values.new(@ctx)
      end

      # Хеш реквизитов той формы, которую читают выражения контракта:
      # ключ верхнего уровня — способ выплаты, значения — из примера запроса.
      def requisites_hash
        branch = current_branch
        return {} if branch.nil?

        branch.fields.each_with_object({}) do |field, hash|
          keys = requisite_keys(branch, field)
          next if keys.nil?

          assign(hash, keys, Generators::Fixtures::Values.dig_path(group_body, [field.name]))
        end
      end

      def requisite_keys(branch, field)
        return nil unless field.role.known?

        expression = @ctx.requisites.expression(branch.key.to_s, field.role.value)
        Expression.keys_under(expression, @ctx.requisites.hash_expression)
      end

      # Ветка, из которой собрана фикстура: та, чьё значение enum стоит в
      # примере запроса.
      def current_branch
        requisites = @parts[:requisites]
        return nil unless requisites.branching?

        value = Generators::Fixtures::Values.dig_path(group_body, [requisites.branch_field.name])
        requisites.branches.find { |branch| branch.value.to_s == value.to_s } ||
          requisites.branches.first
      end

      def group_body
        group = @parts[:requisites].group
        value = group && request_body[group.name]
        value.is_a?(Hash) ? value : {}
      end

      def assign(hash, keys, value)
        *head, last = keys
        nested = head.reduce(hash) { |scope, key| scope[key] ||= {} }
        nested[last] = value
      end
    end
  end
end
