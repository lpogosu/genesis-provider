# frozen_string_literal: true

module SpecGen
  module Rules
    # Строки статусов провайдера → внутренние статусы IR::Roles.
    #
    # `canonical` — маппинг, закреплённый описанием кейса и подтверждённый
    # экспертами, `synonyms` расширяет его словами, которые используют другие
    # провайдеры, а `ambiguous` перечисляет строки, означающие у разных
    # провайдеров разное: их нельзя отображать молча — вместо этого
    # предупреждение и вопрос в report.md. Статус принадлежит ровно одному из
    # трёх разделов: отображённый дважды, он останавливает загрузку.
    class StatusesBook < Book
      FILE = 'statuses.yml'

      # @return [Hash{String => Symbol}] все отображённые статусы,
      #   нормализованные
      attr_reader :index

      # @param status [String] значение статуса из спецификации или ответа
      # @return [Symbol, nil] внутренний статус; nil, если статус неизвестен
      #   или неоднозначен
      def internal_for(status)
        @index[Normalizer.call(status)]
      end

      # @param status [String]
      # @return [Boolean] слово означает у разных провайдеров разное
      def ambiguous?(status)
        @ambiguous.key?(Normalizer.call(status))
      end

      # @param status [String]
      # @return [String, nil] в чём неоднозначность, для report.md
      def ambiguity(status)
        @ambiguous[Normalizer.call(status)]
      end

      # @param status [String]
      # @return [Boolean] маппинг взят из самого описания кейса
      def canonical?(status)
        @canonical.include?(Normalizer.call(status))
      end

      private

      def build
        @index = {}
        @origins = {}
        @canonical = []
        @ambiguous = {}
        load_canonical
        load_synonyms
        load_ambiguous
        report_uncovered
        [@index, @origins, @canonical, @ambiguous].each(&:freeze)
      end

      def load_canonical
        section('canonical').each do |status, internal|
          at = path('canonical', status)
          target = symbol_in(internal, IR::Roles::INTERNAL_STATUS, noun(:internal_status), at)
          next if target.nil?

          key = map_status(status, target, at)
          @canonical << key if key
        end
      end

      def load_synonyms
        section('synonyms').each do |internal, statuses|
          at = path('synonyms', internal)
          target = symbol_in(internal, IR::Roles::INTERNAL_STATUS, noun(:internal_status), at)
          next if target.nil?

          listed = string_list(statuses, noun(:synonyms_of, status: internal), at)
          listed.each_with_index { |status, index| map_status(status, target, "#{at}[#{index}]") }
        end
      end

      def load_ambiguous
        section('ambiguous', Hash, required: false).each do |status, reason|
          at = path('ambiguous', status)
          note = text(reason, noun(:ambiguity_reason, status: status), at)
          key = Normalizer.call(status)
          next if note.nil? || mapped_already?(key, at)

          @ambiguous[key] = note
        end
      end

      def map_status(status, internal, at)
        key = Normalizer.call(status)
        if key.empty?
          fault('statuses.empty', at, status: status.inspect)
          return nil
        end
        return nil if mapped_already?(key, at)

        @index[key] = internal
        @origins[key] = at
        key
      end

      def mapped_already?(key, at)
        owner = @index[key]
        return false if owner.nil?

        fault('statuses.mapped_twice', at, status: key.inspect, owner: owner,
                                           origin: @origins[key])
        true
      end

      def report_uncovered
        missing = IR::Roles::INTERNAL_STATUS - @index.values.uniq
        return if missing.empty?

        fault('statuses.uncovered', path('synonyms'), statuses: missing.join(', '))
      end
    end
  end
end
