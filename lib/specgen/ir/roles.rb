# frozen_string_literal: true

module SpecGen
  module IR
    # Закрытые словари, с которыми работает ядро. Имён полей в платёжных
    # спецификациях бесконечно много, ролей — нет. Поддержка нового
    # провайдера означает новые синонимы в rules/, но никогда новую запись
    # здесь: добавить её — это осознанное изменение модели, которое делается
    # вместе с CLAUDE.md и docs/IR.md.
    #
    # Методы с восклицательным знаком поднимают ArgumentError, потому что
    # значение вне словаря — ошибка программиста внутри генератора, а никогда
    # не плохой пользовательский ввод; плохой ввод становится предупреждением
    # или SpecGen::Error.
    module Roles
      # Роли платёжной области, из CLAUDE.md.
      FIELD = %i[
        amount currency external_id provider_operation_id recipient_type recipient_phone
        bank_code bank_name card_number status error_code error_message created_at
        completed_at idempotency_key signature
      ].freeze

      # Что делает эндпоинт. :unmapped — это результат, а не провал: операция
      # существует и попадает в отчёт, просто ей нет места в контракте, а
      # молча выбросить её выглядело бы как потерянная функциональность.
      OPERATION = %i[
        create_payout create_deposit fetch_status cancel confirm refund balance webhook unmapped
      ].freeze

      # Роли, которые отображаются на метод Provider::BaseService. Отмена,
      # подтверждение, возврат и баланс сознательно остаются снаружи: по
      # CLAUDE.md они генерируются отдельными публичными методами и попадают
      # в report.md с пометкой «не отображено на контракт».
      CONTRACT = %i[create_payout create_deposit fetch_status webhook].freeze

      # Внутренние состояния операции на стороне платформы.
      INTERNAL_STATUS = %i[in_progress approved rejected].freeze

      # Что сгенерированный сервис делает с ответом. :dedup — это случай
      # Idempotency-Key: конфликт, который возвращает прежний результат и
      # потому идёт по успешному пути, а не по ошибочному.
      ERROR_ACTION = %i[reject retry retry_backoff alert escalate dedup].freeze

      # Откуда взялось значение; решает, нужно ли предупреждение.
      SOURCE = %i[structural registry heuristic overlay unknown].freeze

      # Источники, в которых нет сомнения: прочитано из спецификации или
      # сказано человеком.
      CERTAIN_SOURCE = %i[structural overlay].freeze

      # @param role [Symbol]
      # @return [Symbol] сама роль
      # @raise [ArgumentError] если это не известная роль поля
      def self.field!(role)
        Node.assert_member!(FIELD, role, 'роль поля')
      end

      # @param role [Symbol]
      # @return [Symbol] сама роль
      # @raise [ArgumentError] если это не известная роль операции
      def self.operation!(role)
        Node.assert_member!(OPERATION, role, 'роль операции')
      end

      # @param status [Symbol]
      # @return [Symbol] сам статус
      # @raise [ArgumentError] если это не внутренний статус
      def self.internal_status!(status)
        Node.assert_member!(INTERNAL_STATUS, status, 'внутренний статус')
      end

      # @param action [Symbol]
      # @return [Symbol] само действие
      # @raise [ArgumentError] если это не известное действие по ошибке
      def self.error_action!(action)
        Node.assert_member!(ERROR_ACTION, action, 'действие по ошибке')
      end

      # @param source [Symbol]
      # @return [Symbol] сам источник
      # @raise [ArgumentError] если это не известный источник вывода
      def self.source!(source)
        Node.assert_member!(SOURCE, source, 'источник вывода')
      end

      # @param role [Symbol, nil] роль операции
      # @return [Boolean] отображается ли она на метод Provider::BaseService
      def self.contract?(role)
        CONTRACT.include?(role)
      end
    end
  end
end
