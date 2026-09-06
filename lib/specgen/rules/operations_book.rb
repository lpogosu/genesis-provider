# frozen_string_literal: true

module SpecGen
  module Rules
    # Слова и веса, которые превращают путь плюс метод плюс operationId в
    # роль операции.
    #
    # В lib/ не живёт ничего о распознавании эндпоинта: слова, вес каждого
    # сигнала и пороги — данные здесь, поэтому настройка матчера это правка
    # YAML-файла и прогон тестов, а не изменение кода. Загрузчик строг по той
    # же причине, что и остальные книги: роль, с которой ничто не может
    # совпасть, или нулевой вес тихо искривили бы каждую сгенерированную
    # интеграцию.
    class OperationsBook < Book
      include OperationTuning

      FILE = 'operations.yml'
      # Независимые сигналы композитного матчера, в том порядке, в котором их
      # перечисляет строка обоснования.
      SIGNALS = %i[operation_id path_tail path_resource http_method tag request_body
                   unsecured].freeze
      # Числа, которые задают решение целиком, а не один сигнал. Все, кроме
      # `floor`, — доли; `floor` — абсолютная сумма в весах.
      FRACTIONS = %i[partial minimum margin ceiling].freeze
      SCORING = (FRACTIONS + [:floor]).freeze
      # Списки слов, которые может нести любая роль.
      LISTS = %i[verbs nouns resources tail tags].freeze
      # :unmapped — исход, когда не совпало ничего, и никогда не запись.
      ROLES = (IR::Roles::OPERATION - [:unmapped]).freeze
      FRACTION = (0.0..1.0)

      # @return [Array<Symbol>] описанные роли, в порядке справочника
      def roles
        @entries.keys
      end

      # @param role [Symbol] одна из ROLES
      # @return [Hash, nil] :verbs, :nouns, :resources, :tail, :tags,
      #   :http_methods, :tail_parameter, :request_body, :unsecured
      def entry(role)
        @entries[role]
      end

      # @param signal [Symbol] один из SIGNALS
      # @return [Integer] его вес
      def weight(signal)
        @weights.fetch(signal, 0)
      end

      # @param key [Symbol] один из SCORING
      # @return [Float]
      def scoring(key)
        @scoring.fetch(key, 0.0)
      end

      private

      def build
        @weights = load_weights
        @scoring = load_scoring
        @vetoes = load_vetoes
        @pairing = load_pairing
        @entries = load_roles
      end

      def load_weights
        weights = section('weights')
        report_unknown(weights.keys.map(&:to_sym) - SIGNALS, SIGNALS, path('weights'))
        SIGNALS.to_h { |signal| [signal, signal_weight(weights, signal)] }.freeze
      end

      def signal_weight(weights, signal)
        at = path('weights', signal)
        value = integer(weights[signal.to_s], noun(:weight_of, signal: signal), at)
        return value if value.nil? || value.positive?

        fault('operations.weight_zero', at, signal: signal)
      end

      def load_scoring
        scoring = section('scoring')
        report_unknown(scoring.keys.map(&:to_sym) - SCORING, SCORING, path('scoring'))
        values = FRACTIONS.to_h { |key| [key, fraction(scoring[key.to_s], key)] }
        values.merge(floor: above_zero(scoring['floor'], :floor)).freeze
      end

      def above_zero(value, key)
        at = path('scoring', key)
        return value.to_f if value.is_a?(Numeric) && value.positive?

        fault('operations.above_zero', at, key: key, got: describe(value))
      end

      def fraction(value, key, at = path('scoring', key))
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('operations.fraction', at, key: key, range: FRACTION, got: describe(value))
      end

      def load_roles
        entries = {}
        section('roles').each do |name, body|
          role = symbol_in(name, ROLES, noun(:operation_role), path('roles', name))
          entries[role] = compile(role, body) unless role.nil?
        end
        report_missing(entries.keys)
        entries.freeze
      end

      def compile(role, body)
        at = path('roles', role)
        fields = mapping(body, noun(:role_body, role: role), at)
        entry = LISTS.to_h { |key| [key, words(fields[key.to_s], key, at)] }
        entry.merge!(http_methods: methods_of(fields['http_methods'], at),
                     tail_parameter: fields['tail_parameter'] == true,
                     request_body: flag(fields['request_body']),
                     unsecured: fields['unsecured'] == true)
        check_matchable(role, entry, at)
        entry.freeze
      end

      # Слова справочника хранятся нормализованными, поэтому "Pay-Outs",
      # "payOuts" и "pay_outs" в спецификации сравниваются с одной записью.
      def words(value, key, at)
        listed = string_list(value, noun(:list, key: key),
                             "#{at}#{SpecLoader::JsonPath.segment(key)}", required: false)
        listed.map { |word| Normalizer.call(word) }.reject(&:empty?).uniq.freeze
      end

      def methods_of(value, at)
        at = "#{at}.http_methods"
        listed = string_list(value, noun(:list, key: 'http_methods'), at, required: false)
        listed.each_with_index.filter_map do |name, index|
          symbol_in(name.to_s.downcase, IR::Operation::METHODS, noun(:http_method),
                    "#{at}[#{index}]")
        end.freeze
      end

      def flag(value)
        [true, false].include?(value) ? value : nil
      end

      # Роль, у которой пусты все списки, никогда не сможет победить в
      # голосовании — это ошибка в данных, а не любопытный крайний случай.
      def check_matchable(role, entry, at)
        return if LISTS.any? { |key| !entry[key].empty? }

        fault('operations.unmatchable', at, role: role)
      end

      def report_missing(described)
        missing = ROLES - described
        return if missing.empty?

        fault('operations.missing', path('roles'), roles: missing.join(', '))
      end

      def report_unknown(unknown, allowed, at)
        return if unknown.empty?

        fault('operations.unknown_keys', at, keys: unknown.join(', '),
                                             allowed: allowed.join(', '))
      end
    end
  end
end
