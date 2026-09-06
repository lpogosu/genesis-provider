# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Граница контракта в терминах ресурсов спецификации: каких операций и
      # каких схем методы контракта касаются вообще.
      #
      # Нужна, чтобы отличить непокрытое своё от непокрытого чужого. У
      # Paystack 526 непокрытых элементов из 560 описывают подписки, планы,
      # споры и верификацию, у Adyen Payout 116 — четыре операции хранения
      # карт: контракт про выплаты, и его методы этих ресурсов не касаются.
      # Считать их пробелом интеграции — то же самое, что считать пробелом
      # отсутствие в сервисе метода для чужого API.
      #
      # Внутри границы лежат четыре операции: создание (выплата либо
      # депозит), запрос статуса, отмена и точка входящего уведомления —
      # ровно те, для которых генерируются методы контракта, — и все схемы,
      # которые они объявляют.
      class ContractScope
        # Роли операций внутри границы помимо создания и запроса статуса:
        # их контекст отдаёт отдельно, потому что операция создания у одних
        # провайдеров выплата, у других депозит.
        ROLES = %i[cancel webhook].freeze

        # @param ctx [Service::Context]
        def initialize(ctx)
          @ctx = ctx
        end

        # @param operation [IR::Operation]
        # @return [Boolean] операцию вызывает какой-нибудь метод контракта
        def operation?(operation)
          keys.include?(operation.key)
        end

        # @param name [String, nil] имя схемы
        # @return [Boolean] схему разбирает какой-нибудь метод контракта
        def schema?(name)
          schemas.include?(name)
        end

        # @return [Array<IR::Operation>] операции внутри границы контракта
        def operations
          @operations ||= ([@ctx.create_operation, @ctx.status_operation] + by_role).compact.uniq
        end

        private

        def by_role
          @ctx.profile.operations.select { |operation| ROLES.include?(operation.role.value) }
        end

        def keys
          @keys ||= operations.map(&:key)
        end

        def schemas
          @schemas ||= operations.flat_map do |operation|
            operation.responses.map(&:schema) + [operation.request_schema]
          end.compact.uniq
        end
      end
    end
  end
end
