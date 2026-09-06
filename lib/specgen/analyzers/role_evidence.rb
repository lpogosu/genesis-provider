# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Обоснование решения о роли операции: та самая арифметика, которую
    # печатают `--explain` и report.md.
    #
    # Отделено от OperationRole, потому что это другая работа: там решение,
    # здесь его объяснение. Объяснение обязано быть одинаковым у победившей
    # и у проигравшей роли — человеку важно увидеть, кто и с каким отрывом
    # победил, а не только имя роли, — поэтому все три исхода (победа,
    # проигрыш по порогу, отсечка формы) собираются одним классом из одних и
    # тех же чисел.
    class RoleEvidence
      # Причины, по которым роль отсечена формой, а не баллом.
      VETO_REASONS = %i[off_domain method_mismatch list_response].freeze

      # @param book [Rules::OperationsBook] веса и пороги — их печатает
      #   объяснение, чтобы читатель мог проверить арифметику
      # @param ranked [Array<Array(Symbol, Float)>] роли с баллами, лучшая
      #   первой; только те, что прошли отсечки
      # @param cast [Float] суммарный вес проголосовавших сигналов
      # @param rejected [Hash{Symbol => Symbol}] роль => почему отсечена
      def initialize(book:, ranked:, cast:, rejected: {})
        @book = book
        @ranked = ranked
        @cast = cast
        @rejected = rejected
      end

      # @param vote [Hash{Symbol => Float}] голоса победившей роли по сигналам
      # @param score [Float] её сумма
      # @return [String]
      def won(vote, score)
        parts = Rules::OperationsBook::SIGNALS.filter_map do |signal|
          "#{signal} #{number(vote[signal])}" if vote.key?(signal)
        end
        Texts.t('analyzers.operation.match_evidence', parts: parts.join(', '),
                                                      score: number(score), cast: number(@cast),
                                                      runner_up: runner_up_text) + rejected_text
      end

      # @param reason [Symbol] :no_signal, :below_threshold, :ambiguous или
      #   причина отсечки
      # @return [String]
      def lost(reason)
        text = case reason
               when :no_signal then Texts.t('analyzers.operation.no_signal_evidence')
               when *VETO_REASONS then vetoed_text
               else threshold_text(reason)
               end
        text + rejected_text
      end

      # @return [String] "create_payout 8.0, webhook 8.0"
      def scores_text
        @ranked.take(3).reject { |_, score| score.zero? }
               .map { |role, score| "#{role} #{number(score)}" }.join(', ')
      end

      private

      attr_reader :book

      def reason_text(reason)
        Texts.t("analyzers.operation.reason.#{reason}")
      end

      def threshold_text(reason)
        Texts.t('analyzers.operation.lost_evidence',
                reason: reason_text(reason), scores: scores_text, cast: number(@cast),
                floor: number(book.scoring(:floor)), minimum: percent(:minimum),
                margin: percent(:margin))
      end

      def vetoed_text
        Texts.t('analyzers.operation.vetoed_evidence', scores: scores_text, cast: number(@cast))
      end

      # Отсечённая роль называется всегда: она набрала больше всех, и
      # умолчать о ней значило бы скрыть половину решения.
      def rejected_text
        return '' if @rejected.empty?

        listed = @rejected.map do |role, reason|
          Texts.t('analyzers.operation.rejected_role', role: role, reason: reason_text(reason))
        end
        Texts.t('analyzers.operation.rejected', roles: listed.join(', '))
      end

      def runner_up_text
        runner_up = @ranked[1]
        return Texts.t('analyzers.operation.no_runner_up') if runner_up.nil? ||
                                                              runner_up.last.zero?

        Texts.t('analyzers.operation.runner_up', role: runner_up.first,
                                                 score: number(runner_up.last))
      end

      def percent(key)
        format('%<share>d%%', share: book.scoring(key) * 100)
      end

      def number(value)
        format('%.1f', value.to_f)
      end
    end
  end
end
