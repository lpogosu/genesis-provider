# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Какая операция создаёт ресурс и какая опрашивает его статус — решается
    # парой, а не поодиночке.
    #
    # Пока каждая роль искала своего лучшего кандидата отдельно, спецификация
    # с несколькими одинаково уверенными кандидатами давала сервис, который
    # создаёт один ресурс, а статус читает у другого: Adyen Transfers
    # создавал `/transfers`, а опрашивал `/transactions/{id}`, Moov —
    # `/micro-deposits/{id}`. Это худший класс ошибки: результат выглядит
    # рабочим и молча неверен.
    #
    # Поэтому перебираются пары «создание + опрос», и каждая оценивается
    # суммой уверенностей обеих ролей плюс вес связывающих их правил
    # (ResourceAffinity и Link Object). Отмена привязывается к тому же
    # ресурсу, что и выбранная пара. Всё, что осталось неоднозначным —
    # равные баллы или несвязанная пара, — уходит в предупреждения, потому
    # что молчать об этом нельзя.
    class OperationPairing
      # Слот роли в сгенерированном сервисе и всё, чем объясняется выбор.
      #
      #   role       роль, чей слот занят
      #   operation  выбранная операция
      #   partner    вторая половина пары: у создания это опрос статуса, у
      #              опроса и отмены — создание; nil, если пары нет
      #   rules      сработавшие правила связывания
      #   link       OperationLinks::Link, если выбор сделан формальной ссылкой
      #   tied       кандидаты с той же уверенностью, в порядке спецификации;
      #              пуст, если равных не было
      Choice = Struct.new(:role, :operation, :partner, :rules, :link, :tied, keyword_init: true)

      CREATE = %i[create_payout create_deposit].freeze
      STATUS = :fetch_status
      CANCEL = :cancel
      EPSILON = 1e-9

      # @param operations [Array<IR::Operation>] в порядке спецификации
      # @param book [Rules::OperationsBook] веса правил связывания
      # @param links [Array<OperationLinks::Link>] прочитанные Link Object
      def initialize(operations:, book:, links: [])
        @operations = operations
        @book = book
        @links = links
      end

      # @return [Hash{Symbol => Choice}] слот (:create, :status, :cancel) =>
      #   выбор; слот без кандидатов отсутствует
      def call
        create, status = best_pair
        rules = create && status ? rules_for(create, status) : []
        { create: choice(create&.role&.value, create, status, rules, creates),
          status: choice(STATUS, status, create, rules, statuses(creates)),
          cancel: cancel_choice(create || status) }.compact
      end

      private

      attr_reader :book

      # Роль слота, а не роль операции: цель формальной ссылки занимает слот
      # опроса статуса, даже если голоса ей этой роли не дали.
      def choice(role, operation, partner, rules, pool)
        return nil if operation.nil?

        Choice.new(role: role, operation: operation, partner: partner, rules: rules,
                   link: link_between(partner, operation), tied: tied(pool, operation))
      end

      def cancel_choice(partner)
        pool = candidates(CANCEL)
        chosen = partner.nil? ? best(pool) : best_by(pool) { |op| bond(partner, op) }
        return nil if chosen.nil?

        rules = partner ? rules_for(partner, chosen) : []
        Choice.new(role: CANCEL, operation: chosen, partner: partner, rules: rules,
                   link: link_between(partner, chosen), tied: tied(pool, chosen))
      end

      # Пара с наибольшей суммой: уверенность обеих ролей плюс вес правил,
      # которые их связывают. Порядок перебора — порядок спецификации,
      # поэтому при полном равенстве выигрывает объявленная раньше.
      # @return [Array(IR::Operation, IR::Operation)]
      def best_pair
        listed = creates
        polled = statuses(listed)
        return [best(listed), best(polled)] if listed.empty? || polled.empty?

        best_by(listed.product(polled)) { |pair| bond(*pair) }.first(2)
      end

      def bond(create, status)
        confidence(create) + confidence(status) + weight_of(rules_for(create, status)) +
          resource_bonus(create) - depth_penalty(create, status)
      end

      def weight_of(rules)
        rules.sum { |rule| book.pairing(rule).to_f }
      end

      # Насколько имя ресурса похоже на главный денежный документ: место в
      # `resource_priority`. Именно это отличает `/transfer` от
      # `/paymentrequest`, когда голоса равны.
      def resource_bonus(create)
        listed = book.pairing(:resource_priority)
        index = listed.index(ResourceAffinity.tail(create.path))
        return 0.0 if index.nil?

        book.pairing(:resource).to_f * (listed.size - index) / listed.size
      end

      def depth_penalty(create, status)
        book.pairing(:depth_penalty).to_f *
          (ResourceAffinity.depth(create.path) + ResourceAffinity.depth(status.path))
      end

      def rules_for(create, status)
        found = link_between(create, status) ? [:link] : []
        found + ResourceAffinity.rules(create, status)
      end

      def link_between(create, status)
        return nil if create.nil? || status.nil?

        @links.find do |link|
          (link.from == create.key && link.to == status.key) ||
            (link.from == status.key && link.to == create.key)
        end
      end

      def creates
        @creates ||= CREATE.map { |role| candidates(role) }.find { |list| !list.empty? } || []
      end

      # Цель формальной ссылки становится кандидатом на опрос статуса, даже
      # если голоса ей этой роли не дали: ссылка — прочитанное, а не вывод.
      def statuses(listed)
        @statuses ||= (candidates(STATUS) + listed.flat_map { |create| promoted(create) }).uniq
      end

      def promoted(create)
        @links.filter_map do |link|
          next unless link.from == create.key

          operation = @operations.find { |candidate| candidate.key == link.to }
          operation if operation&.http_method == :get && promotable?(operation)
        end
      end

      def promotable?(operation)
        operation.unmapped? || operation.role.value == STATUS
      end

      def candidates(role)
        @operations.select { |operation| operation.role.value == role }
      end

      def confidence(operation)
        operation.role.confidence.to_f
      end

      def best(pool)
        best_by(pool) { |operation| confidence(operation) }
      end

      # Детерминированный максимум: при равенстве побеждает объявленный
      # раньше, а не тот, кого вернул хеш.
      def best_by(pool)
        pool.each_with_index.min_by { |item, index| [-yield(item), index] }&.first
      end

      # Кандидаты с той же уверенностью, что у выбранного: ничья, о которой
      # обязано узнать report.md.
      def tied(pool, chosen)
        return [] if chosen.nil?

        top = confidence(chosen)
        equal = pool.select { |item| (confidence(item) - top).abs < EPSILON }
        equal.size > 1 ? equal : []
      end
    end
  end
end
