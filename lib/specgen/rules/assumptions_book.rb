# frozen_string_literal: true

module SpecGen
  module Rules
    # Допущения проекта как данные — то, что раздел «Принятые допущения»
    # сгенерированного INTEGRATION.md печатает у каждого провайдера.
    #
    # Генератор не читает docs/ репозитория: инструмент обязан работать из
    # любого каталога, а документация — журнал для людей. Поэтому источник
    # истины для генератора — rules/assumptions.yml, а docs/ASSUMPTIONS.md
    # правится тем же коммитом. Книга следит за тем, чтобы номера не
    # повторялись, снятое допущение говорило, чем заменено, а у каждой
    # записи были текст и источник: допущение без источника — это догадка,
    # выданная за факт.
    class AssumptionsBook < Book
      FILE = 'assumptions.yml'
      STATUSES = %i[active withdrawn].freeze

      # Одна запись справочника.
      #
      #   id           номер, как в docs/ASSUMPTIONS.md
      #   text         само допущение
      #   source       откуда оно взялось
      #   affects      где влияет
      #   status       :active | :withdrawn
      #   replaced_by  чем заменено, для :withdrawn
      #   documented   печатать ли в INTEGRATION.md
      Assumption = Struct.new(:id, :text, :source, :affects, :status, :replaced_by, :documented,
                              keyword_init: true) do
        # @return [Boolean]
        def active?
          status == :active
        end
      end

      # @return [Array<Assumption>] все записи в порядке справочника
      attr_reader :all

      # @return [Array<Assumption>] действующие допущения, которые
      #   INTEGRATION.md обязан перечислить
      def documented
        all.select { |item| item.active? && item.documented }
      end

      # @param id [Integer]
      # @return [Assumption, nil]
      def find(id)
        all.find { |item| item.id == id }
      end

      private

      def build
        @all = []
        seen = {}
        section('assumptions', Array).each_with_index do |body, index|
          item = read(body, path('assumptions', index))
          next if item.nil?

          check_unique(item, seen, path('assumptions', index))
          @all << item
        end
        @all.freeze
      end

      def read(body, at)
        fields = mapping(body, noun(:assumption_body), at)
        return nil if fields.empty?

        item = Assumption.new(**required(fields, at), **optional(fields, at))
        check_replacement(item, at)
        item.freeze
      end

      def required(fields, at)
        { id: integer(fields['id'], noun(:assumption_id), "#{at}.id", range: (1..)),
          text: text(fields['text'], noun(:assumption_text), "#{at}.text"),
          source: text(fields['source'], noun(:assumption_source), "#{at}.source") }
      end

      def optional(fields, at)
        { affects: fields['affects'].to_s, replaced_by: fields['replaced_by'],
          status: symbol_in(fields.fetch('status', 'active'), STATUSES, noun(:assumption_status),
                            "#{at}.status"),
          documented: fields.fetch('documented', true) == true }
      end

      def check_replacement(item, at)
        return unless item.status == :withdrawn && item.replaced_by.to_s.strip.empty?

        fault('assumptions.withdrawn_without_replacement', "#{at}.replaced_by", id: item.id)
      end

      def check_unique(item, seen, at)
        return if item.id.nil?
        return seen[item.id] = at unless seen.key?(item.id)

        fault('assumptions.duplicate_id', "#{at}.id", id: item.id, other: seen[item.id])
      end
    end
  end
end
