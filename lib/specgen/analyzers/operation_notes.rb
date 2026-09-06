# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Что сказать человеку об одной прочитанной операции: нет operationId,
    # роль неоднозначна, роль отсечена по форме, роли нет места в контракте.
    #
    # Отделено от OperationAnalyzer по той же границе, что RoleEvidence от
    # OperationRole: там чтение спецификации, здесь объяснение решений.
    # Предупреждения возвращаются списком в порядке, в котором их читает
    # отчёт, а записывает их анализатор — единственный, кто владеет профилем.
    class OperationNotes
      # Роли, для которых у контракта нет метода. Они распознаны, а не
      # проигнорированы: генератор даёт каждой отдельный публичный метод, а
      # отчёт говорит «вне контракта».
      OFF_CONTRACT = (IR::Roles::OPERATION - IR::Roles::CONTRACT - [:unmapped]).freeze

      # @param operation [IR::Operation] уже собранная операция
      # @param result [OperationRole::Result] решение матчера ролей
      # @param at [String] JSONPath операции
      def initialize(operation:, result:, at:)
        @operation = operation
        @result = result
        @at = at
      end

      # Два разных молчания — два разных предупреждения: плотная борьба
      # настоящих кандидатов это неоднозначность, которую разрешает человек,
      # а полное отсутствие набранных очков означает, что спецификация не
      # говорит ничего, что мы могли бы прочитать.
      # @return [Array<Note>]
      def call
        [missing_id, role_note, off_contract].compact
      end

      private

      attr_reader :operation, :result, :at

      def role_note
        case result.reason
        when :ambiguous then ambiguous('ambiguous')
        when :below_threshold then ambiguous('below_threshold')
        when :no_signal then no_role
        when *RoleEvidence::VETO_REASONS then vetoed
        end
      end

      def missing_id
        return nil unless operation.id.nil?

        note(:operation_id_missing, t('id_missing', key: operation.key.inspect), :info)
      end

      def no_role
        note(:operation_unmapped, t('unmapped', scores: scores))
      end

      # Роль взята ниже порога или в плотной борьбе: по третьему уровню
      # доверия из docs/PRINCIPLES.md лучший кандидат всё равно присваивается, но
      # человек должен об этом узнать из отчёта.
      def ambiguous(key)
        note(:operation_role_ambiguous, t(key, scores: scores))
      end

      # Роль набрала больше всех голосов, но не прошла отсечку формы. Это
      # решение, а не сомнение: ложная роль затащила бы посторонний ресурс
      # спецификации в контракт молча, а :unmapped виден в отчёте и получает
      # отдельный публичный метод.
      def vetoed
        role, reason = result.rejected.first
        note(:operation_unmapped,
             t('vetoed', role: role, reason: Texts.t("analyzers.operation.reason.#{reason}")),
             :info)
      end

      def off_contract
        role = operation.role.value
        return nil unless OFF_CONTRACT.include?(role)

        note(:operation_unmapped, t('off_contract', role: role), :info)
      end

      # @return [String] "create_payout 8.0, webhook 8.0 из 13.0 поданных голосов"
      def scores
        listed = result.scores.take(3).reject { |_, score| score.zero? }
                       .map { |role, score| "#{role} #{format('%.1f', score)}" }
        t('scores', scores: listed.join(', '), cast: format('%.1f', result.cast))
      end

      def note(code, message, severity = :warning)
        Note.new(code: code, message: message, json_path: at, severity: severity)
      end

      def t(key, **params)
        Texts.t("analyzers.operation.#{key}", **params)
      end
    end
  end
end
