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
      FRACTION = (0.0..1.0)

      # @return [Hash{String => Symbol}] все отображённые статусы,
      #   нормализованные
      attr_reader :index
      # @return [Array<String>] ведущие слова, меняющие смысл статуса за ними
      attr_reader :modifiers
      # @return [Array<String>] ведущие слова, по которым читается всё имя
      attr_reader :heads
      # @return [Array<String>] хвостовые слова, не меняющие исход
      attr_reader :suffixes
      # @return [Float] уверенность статуса, прочитанного по хвосту
      #   составного имени
      attr_reader :tail_confidence

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

      # @param tokens [Array<String>] отброшенные ведущие токены имени
      # @return [String, nil] первый из них, меняющий смысл статуса
      def modifier(tokens)
        (tokens & @modifiers).first
      end

      # Голова составного имени, по которой читается всё имя целиком.
      # @param tokens [Array<String>] токены имени
      # @return [String, nil] первый токен, если он объявлен в `heads`
      def head(tokens)
        word = tokens.first
        @heads.include?(word) ? word : nil
      end

      # @param tokens [Array<String>] токены имени
      # @return [String, nil] последний токен, если он объявлен в `suffixes`
      def suffix(tokens)
        word = tokens.last
        tokens.size > 1 && @suffixes.include?(word) ? word : nil
      end

      # Слово, по которому видно, что значение называет тип операции, а не
      # её исход.
      # @param tokens [Array<String>] токены имени
      # @return [String, nil]
      def type_word(tokens)
        (tokens & @not_status_words).first
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
        load_reading
        report_uncovered
        [@index, @origins, @canonical, @ambiguous, @modifiers, @heads, @suffixes,
         @not_status_words].each(&:freeze)
      end

      # Как читать составное имя: какие ведущие слова снимать нельзя, по
      # какой голове читается всё имя, какой хвост снимается без потери
      # смысла и с какой уверенностью читается то, что осталось.
      def load_reading
        @modifiers = words('modifiers')
        @heads = words('heads')
        @suffixes = words('suffixes')
        @not_status_words = words('not_status_words')
        @tail_confidence = fraction('tail_confidence')
        check_heads
        check_not_statuses('suffixes', @suffixes)
        check_not_statuses('not_status_words', @not_status_words)
      end

      def words(key)
        string_list(data[key], noun(key.to_sym), path(key), required: false)
          .map { |word| Normalizer.call(word) }
      end

      # Голова обязана быть статусом, отображённым в in_progress: правило
      # головы отбрасывает часть имени, и единственное направление ошибки,
      # которое при этом допустимо, — оставить операцию в опросе.
      def check_heads
        @heads.each_with_index do |word, index|
          next if @index[word] == :in_progress

          fault('statuses.head_not_in_progress', "#{path('heads')}[#{index}]",
                head: word.inspect, internal: (@index[word] || '-').to_s)
        end
      end

      # Слово, которое само по себе статус, не может быть ни снимаемым
      # хвостом, ни признаком «это не статус».
      def check_not_statuses(key, listed)
        listed.each_with_index do |word, index|
          next unless @index.key?(word) || @ambiguous.key?(word)

          fault('statuses.word_is_status', "#{path(key)}[#{index}]", key: key, word: word.inspect)
        end
      end

      def fraction(key)
        value = data[key]
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('statuses.confidence', path(key), key: key, range: FRACTION, got: describe(value))
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
