# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Как объяснить выбор пары «создание — опрос статуса»: обоснование для
    # роли и предупреждения для отчёта.
    #
    # Отделено от OperationPairing по той же причине, по которой RoleEvidence
    # отделён от OperationRole: там решение, здесь его объяснение. Молчать
    # нельзя ни о ничьей (несколько кандидатов с равной уверенностью, и
    # что-то должно было её разрешить), ни о несвязанной паре (сервис создаёт
    # один ресурс, а читает другой). Оба случая получают предупреждение с
    # перечнем кандидатов, а несвязанная пара — ещё и готовый фрагмент
    # overlay: Link Object, которым спецификация выразила бы связь сама.
    class PairingNotes
      # Имя предлагаемой ссылки в overlay-фрагменте: машинный текст, он не
      # переводится.
      LINK_NAME = 'fetchStatus'
      DEFAULT_PARAMETER = 'id'

      # Текст, который дописывается к обоснованию роли. nil, когда выбирать
      # было не из чего и рассказывать нечего: обоснование роли остаётся
      # прежним, а отчёт — байт в байт тем же.
      # @param choice [OperationPairing::Choice]
      # @return [String, nil]
      def self.evidence(choice)
        return link_evidence(choice.link) if choice.link
        return nil if choice.partner.nil? || (choice.tied.empty? && !choice.rules.empty?)
        return t('evidence_unrelated', partner: choice.partner.key) if choice.rules.empty?

        t('evidence', partner: choice.partner.key, rules: rules_text(choice))
      end

      # @param link [OperationLinks::Link]
      # @return [String]
      def self.link_evidence(link)
        listed = link.parameters.map { |name, value| "#{name} = #{value}" }.join(', ')
        text = t('link_evidence', name: link.name, status: link.status, from: link.from,
                                  to: link.to)
        listed.empty? ? text : text + t('link_parameters', expressions: listed)
      end

      # @param choice [OperationPairing::Choice]
      # @return [String] сработавшие правила словами
      def self.rules_text(choice)
        choice.rules.map { |rule| t("rule.#{rule}", word: word_of(choice, rule)) }.join(', ')
      end

      # @return [String] то, чем именно совпали две операции
      def self.word_of(choice, rule)
        producer, consumer = ordered(choice)
        return ResourceAffinity.tail(producer.path).to_s if rule == :container
        return ResourceAffinity.shared_schema(producer, consumer).to_s if rule == :schema

        ''
      end

      # @return [Array(IR::Operation, IR::Operation)] продюсер и консьюмер
      def self.ordered(choice)
        return [choice.operation, choice.partner] if OperationPairing::CREATE.include?(choice.role)

        [choice.partner, choice.operation]
      end

      def self.t(key, **params)
        Texts.t("analyzers.pairing.#{key}", **params)
      end

      # @param choices [Hash{Symbol => OperationPairing::Choice}] слоты
      def initialize(choices)
        @choices = choices
      end

      # @return [Array<Note>] в порядке слотов
      def notes
        @choices.values.filter_map { |choice| tie(choice) } + [mismatch].compact
      end

      private

      # Ничья решается связью с ресурсом, а если и её нет — порядком
      # объявления, и тогда это настоящий подброс монетки, о котором человек
      # обязан узнать.
      def tie(choice)
        return nil if choice.tied.size < 2

        message = t('tie_message', role: choice.role, confidence: confidence(choice.operation),
                                   candidates: listed(choice.tied),
                                   chosen: choice.operation.key, reason: tie_reason(choice))
        Note.new(code: :operation_tie, message: message,
                 severity: choice.rules.empty? ? :warning : :info,
                 json_path: choice.operation.json_path)
      end

      def tie_reason(choice)
        return t('tie_reason_order') if choice.rules.empty? || choice.partner.nil?

        t('tie_reason_rules', partner: choice.partner.key,
                              rules: self.class.rules_text(choice))
      end

      # Пара, которую спецификация ничем не связывает: создаём один ресурс,
      # опрашиваем другой.
      def mismatch
        create = @choices[:create]
        status = @choices[:status]
        return nil if create.nil? || status.nil? || !status.rules.empty?

        message = t('mismatch_message', create: endpoint(create.operation),
                                        status: endpoint(status.operation))
        Note.new(code: :operation_pair_mismatch, message: message, severity: :warning,
                 json_path: create.operation.json_path,
                 suggested_overlay: fragment(create.operation, status.operation))
      end

      # @return [String, nil] Link Object, которым это лечится
      def fragment(create, status)
        response = create.success_responses.find(&:json_path)
        return nil if response.nil?

        t('link_overlay', path: response.json_path, name: LINK_NAME,
                          operation: status.id || status.key, parameter: path_parameter(status))
      end

      def path_parameter(status)
        status.parameters_in(:path).first&.name || DEFAULT_PARAMETER
      end

      def listed(operations)
        operations.map { |operation| "#{operation.key} (#{endpoint(operation)})" }.join(', ')
      end

      def endpoint(operation)
        "#{operation.http_method.to_s.upcase} #{operation.path}"
      end

      def confidence(operation)
        format('%.2f', operation.role.confidence.to_f)
      end

      def t(key, **params)
        self.class.t(key, **params)
      end
    end
  end
end
