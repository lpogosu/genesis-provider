# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Два измерения покрытия, которые считаются по полям схем: что сервис
      # отправляет и что читает.
      #
      # Исходящие тела считаются по операциям (тело собирается для каждой
      # операции отдельно), входящие — по схемам (одна схема разбирается
      # одинаково, в каком бы ответе ни встретилась). Покрытым считается
      # только поле, у которого в коде есть выражение: обязательное поле,
      # попавшее в payload с TODO и значением по умолчанию, не покрыто —
      # запрос с ним не уйдёт.
      class CoverageFields < Base
        # Роли, которые сгенерированный сервис читает из входящих тел:
        # статус, идентификатор провайдера, код ошибки и внешний
        # идентификатор для поиска операции по уведомлению.
        READ_ROLES = %i[status provider_operation_id error_code external_id].freeze

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}]
        def initialize(ctx, parts)
          super
          @fields = Generators::SchemaFields.new(ctx)
        end

        # @return [Dimension] поля тел запросов, которые сервис отправляет
        def request
          gaps = request_entries.reject { |operation, entry| request_covered?(operation, entry) }
                                .map { |operation, entry| request_gap(operation, entry) }
          build('request_fields', request_entries.size, gaps, out_of_scope: skipped_optional)
        end

        # Из знаменателя второй цифры входящие поля уходят целиком, кроме
        # прочитанных: поле, чья роль не входит в READ_ROLES, и поле без
        # роли методам контракта класть некуда — они не выбраны, а не
        # упущены. Поле события уведомления сервис читает, и оно остаётся.
        # @return [Dimension] поля тел ответов и уведомлений, которые сервис читает
        def response
          gaps = response_entries.reject { |_name, entry| response_covered?(entry) }
                                 .map { |name, entry| response_gap(name, entry) }
          build('response_fields', response_entries.size, gaps, out_of_scope: gaps.size)
        end

        private

        # Необязательное поле без роли в payload не идёт намеренно (docs/PRINCIPLES.md,
        # «Что генерируем при неполной спеке»), поэтому пробелом интеграции
        # оно не является. Обязательное без роли остаётся в знаменателе: оно
        # уходит в payload с TODO, и это настоящий пробел.
        def skipped_optional
          request_entries.count { |_operation, entry| optional_without_role?(entry.field) }
        end

        def optional_without_role?(field)
          !field.role.known? && !field.required? && !field.conditionally_required?
        end

        # @return [Array<Array(IR::Operation, Generators::SchemaFields::Entry)>]
        def request_entries
          @request_entries ||= outgoing.flat_map do |operation|
            @fields.of(operation.request_schema).map { |entry| [operation, entry] }
          end
        end

        def outgoing
          profile.operations.reject { |operation| operation.role.value == :webhook }
        end

        def request_covered?(operation, entry)
          builds_payload?(operation) && expression?(entry.field)
        end

        # Тело собирают операция создания и каждая операция вне контракта со
        # своей схемой тела. Вторая операция создания остаётся непокрытой:
        # контракт даёт один метод создания.
        def builds_payload?(operation)
          create?(operation) || !parts[:extras].payload_builder(operation).nil?
        end

        def create?(operation)
          operation.equal?(ctx.create_operation)
        end

        # Выражение у поля есть, если его даёт платформа, константа валюты
        # сервиса или таблица реквизитов в своей ветке. Роль, для которой
        # выражения нет ни там, ни там, покрытием не считается: поле уйдёт с
        # TODO и nil.
        def expression?(field)
          return false unless field.role.known?
          return true unless ctx.accessor(field.role.value).nil?
          return true unless ctx.currency_constant_for(field.role.value).nil?

          parts[:requisites].covers?(field)
        end

        def request_gap(operation, entry)
          key, params = request_reason(operation, entry.field)
          Gap.new(element: "#{operation.key}: #{entry.path}", reason_key: key, params: params,
                  foreign: !scope.operation?(operation))
        end

        # @return [Array(Symbol, Hash)] ключ причины и её подстановки
        def request_reason(operation, field)
          unless builds_payload?(operation)
            return [:gap_field_other_operation, { key: operation.key }]
          end
          return [:gap_field_no_accessor, { role: field.role.value }] if field.role.known?
          return [:gap_field_required_todo, {}] if required?(field)

          [:gap_field_optional_skipped, {}]
        end

        def required?(field)
          field.required? || field.conditionally_required?
        end

        # Входящие тела: ответы всех операций плюс тело уведомления, которое
        # в спецификации объявлено запросом ко входящей точке.
        # @return [Array<Array(String, Generators::SchemaFields::Entry)>]
        def response_entries
          @response_entries ||= incoming_schemas.flat_map do |name|
            @fields.of(name).map { |entry| [name, entry] }
          end
        end

        def incoming_schemas
          names = profile.operations.flat_map do |operation|
            responses = operation.responses.map(&:schema)
            operation.role.value == :webhook ? responses + [operation.request_schema] : responses
          end
          names.compact.uniq
        end

        def response_covered?(entry)
          return true if event_field?(entry.field)

          entry.field.role.known? && READ_ROLES.include?(entry.field.role.value)
        end

        def event_field?(field)
          found = parts[:callback].event_field
          !found.nil? && found.equal?(field)
        end

        def response_gap(name, entry)
          key, params = response_reason(entry.field)
          Gap.new(element: "#{name}.#{entry.path}", reason_key: key, params: params,
                  foreign: !scope.schema?(name))
        end

        # @return [Array(Symbol, Hash)] ключ причины и её подстановки
        def response_reason(field)
          roles = { base: code(ctx.contract.base_class), roles: codes(READ_ROLES) }
          return [:gap_response_role_unknown, roles] unless field.role.known?

          [:gap_response_role_unused, roles.merge(role: code(field.role.value))]
        end
      end
    end
  end
end
