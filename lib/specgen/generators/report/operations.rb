# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Раздел 4: операции вне контракта и операции без роли. Ничего не
      # выброшено молча — для каждой сгенерирован публичный метод, и здесь
      # сказано, какой именно и что с ним делать.
      #
      # Расширения `x-specgen-role` для операции в модели нет (таблица
      # расширений — docs/IR.md, оно адресует свойство схемы или параметр),
      # поэтому роль операции закрепляется синонимом в rules/operations.yml.
      class Operations < Base
        # @return [Array<String>] заголовки таблицы
        def headers
          %w[key_col endpoint_col role_col generated_col action_col].map { |key| t(key) }
        end

        # @return [Array<Array<String>>] по строке на операцию вне контракта
        def rows
          parts[:extras].entries.map { |operation, method| row(operation, method) }
        end

        # @return [Boolean] есть ли хоть одна такая операция
        def any?
          !parts[:extras].entries.empty?
        end

        private

        def row(operation, method)
          [code(operation.key), endpoint(operation), role(operation),
           code("#{method.name}(#{method.params.map { |param| param[:name] }.join(', ')})"),
           action(operation)]
        end

        def role(operation)
          return t('role_unmapped') if operation.unmapped?

          t('role_known', role: code(operation.role.value), confidence: label(operation.role))
        end

        def action(operation)
          return t('action_unmapped_operation') if operation.unmapped?

          t('action_outside_contract', base: code(ctx.contract.base_class))
        end
      end
    end
  end
end
