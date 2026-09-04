# frozen_string_literal: true

module SpecGen
  module IR
    # Корень IR: всё, что генераторам нужно знать об одном провайдере, и
    # ничего о том, как это было загружено. Анализаторы заполняют свою часть и
    # добавляют предупреждения; после стадии анализа профиль по договорённости
    # только читают.
    #
    #   info         Info
    #   servers      [Server]
    #   auth         Auth или nil (nil: ни один анализатор ещё не смотрел;
    #                спецификация, не объявляющая авторизации, даёт Auth с
    #                типом :none)
    #   operations   [Operation] в порядке спецификации
    #   schemas      {имя => Schema}
    #   status_map   [StatusMapping]
    #   error_map    [ErrorRule]
    #   webhooks     [Webhook]
    #   units        Units или nil (nil: поля суммы нет нигде)
    #   idempotency  Idempotency или nil (nil: подходящего заголовка нет нигде)
    #   conditions   [Condition] — другие условия взаимодействия, в порядке
    #                спецификации
    #   warnings     [Warning]
    ProviderProfile = Struct.new(:info, :servers, :auth, :operations, :schemas, :status_map,
                                 :error_map, :webhooks, :units, :idempotency, :conditions,
                                 :warnings, keyword_init: true)

    # Значения по умолчанию, сбор предупреждений и выборки ProviderProfile.
    class ProviderProfile
      include Node

      # @param info [Info, nil]
      # @param servers [Array<Server>]
      # @param auth [Auth, nil]
      # @param operations [Array<Operation>]
      # @param schemas [Hash{String => Schema}]
      # @param status_map [Array<StatusMapping>]
      # @param error_map [Array<ErrorRule>]
      # @param webhooks [Array<Webhook>]
      # @param units [Units, nil]
      # @param idempotency [Idempotency, nil]
      # @param conditions [Array<Condition>]
      # @param warnings [Array<Warning>]
      # @raise [ArgumentError]
      def initialize(info: nil, servers: [], auth: nil, operations: [], schemas: {}, status_map: [],
                     error_map: [], webhooks: [], units: nil, idempotency: nil, conditions: [],
                     warnings: [])
        Node.assert_optional!(info, Info, 'info')
        Node.assert_optional!(auth, Auth, 'auth')
        Node.assert_optional!(units, Units, 'units')
        Node.assert_optional!(idempotency, Idempotency, 'idempotency')
        super
      end

      # Записывает предупреждение. Анализаторы вызывают этот метод, а не
      # трогают массив.
      # @param code [Symbol] один из Warning::CODES
      # @param message [String]
      # @param json_path [String, nil]
      # @param severity [Symbol] одна из Warning::SEVERITIES
      # @param suggested_overlay [String, nil]
      # @return [Warning] записанное предупреждение
      def warn(code, message, json_path: nil, severity: :warning, suggested_overlay: nil)
        warning = Warning.new(code:, message:, json_path:, severity:, suggested_overlay:)
        warnings << warning
        warning
      end

      # @return [Array<Warning>] по серьёзности, затем по JSONPath, затем по коду
      def sorted_warnings
        warnings.sort_by(&:sort_key)
      end

      # @return [Hash{Symbol => Array<Warning>}] каждая серьёзность как ключ,
      #   самая серьёзная первой, каждый список отсортирован
      def warnings_by_severity
        sorted = sorted_warnings
        Warning::SEVERITIES.to_h { |severity| [severity, sorted.select { |w| w.severity == severity }] }
      end

      # @param severity [Symbol, nil] ограничиться одной серьёзностью
      # @return [Boolean]
      def warnings?(severity = nil)
        return !warnings.empty? if severity.nil?

        warnings.any? { |warning| warning.severity == severity }
      end

      # @param role [Symbol] одна из Roles::OPERATION
      # @return [Array<Operation>] в порядке спецификации
      def operations_by_role(role)
        Roles.operation!(role)
        operations.select { |operation| operation.role.value == role }
      end

      # @param role [Symbol] одна из Roles::OPERATION
      # @return [Operation, nil] первая операция с такой ролью
      def operation_for(role)
        operations_by_role(role).first
      end

      # @param key [String] Operation#key
      # @return [Operation, nil]
      def operation(key)
        operations.find { |operation| operation.key == key }
      end

      # @param name [String]
      # @return [Schema, nil]
      def schema(name)
        schemas[name]
      end

      # @return [Array<ErrorRule>] в порядке таблицы
      def sorted_error_map
        error_map.sort_by(&:sort_key)
      end

      # Поля в порядке объявления; схемы по имени, правила ошибок по
      # селектору, предупреждения по серьёзности — чтобы вывод никогда не
      # зависел от того, в каком порядке отработали анализаторы.
      # @return [Hash{Symbol => Object}]
      def to_h
        by_name = schemas.keys.sort
        super.merge(
          schemas: by_name.to_h { |name| [name, Node.dump(schemas[name])] },
          error_map: sorted_error_map.map(&:to_h),
          warnings: sorted_warnings.map(&:to_h)
        )
      end
    end
  end
end
