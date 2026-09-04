# frozen_string_literal: true

module SpecGen
  module Rules
    # Заголовок Idempotency-Key: как его называют в индустрии и как
    # сгенерированный сервис получает значение.
    #
    # Ключ выводится из `operation.id` по UUID v5 с фиксированным
    # пространством имён, поэтому повтор даёт тот же ключ, и провайдер
    # возвращает прежний результат вместо второй выплаты. Поэтому же здесь
    # ничто не может быть случайным: пространство имён — константа в
    # справочнике, а пространство имён, не являющееся UUID, останавливает
    # загрузку.
    class IdempotencyBook < Book
      FILE = 'idempotency.yml'
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      STATUS_RANGE = (100..599)

      # @return [String, nil] имя, которое отправляет сгенерированный сервис
      attr_reader :canonical_header
      # @return [Array<String>] имена заголовков, как написаны в справочнике
      attr_reader :aliases
      # @return [Array<String>] те же имена, нормализованные для поиска
      attr_reader :normalized
      # @return [Symbol, nil] одна из IR::Idempotency::STRATEGIES
      attr_reader :default_strategy
      # @return [String, nil] фиксированное пространство имён UUID v5
      attr_reader :namespace
      # @return [Integer, nil] код, которым провайдер отвечает на повтор
      attr_reader :conflict_status

      # @param header [String] имя заголовка, встреченное в спецификации
      # @return [Boolean] заголовок — известный ключ идемпотентности
      def alias?(header)
        @normalized.include?(Normalizer.call(header))
      end

      # @return [Boolean] отправлять ключ и там, где спецификация помечает
      #   заголовок необязательным
      def send_when_optional?
        @send_when_optional
      end

      private

      def build
        @canonical_header = text(data['canonical_header'], noun(:canonical_header),
                                 path('canonical_header'))
        @aliases = string_list(data['aliases'], noun(:list, key: 'aliases'), path('aliases'))
        @normalized = collect_aliases.freeze
        load_strategy
      end

      def load_strategy
        @default_strategy = symbol_in(data['default_strategy'], IR::Idempotency::STRATEGIES,
                                      noun(:idempotency_strategy), path('default_strategy'))
        @conflict_status = integer(data['conflict_status'], noun(:conflict_status),
                                   path('conflict_status'), range: STATUS_RANGE)
        @send_when_optional = data.fetch('send_when_optional', true) == true
        @namespace = uuid_namespace
      end

      def uuid_namespace
        at = path('uuid_v5_namespace')
        value = text(data['uuid_v5_namespace'], noun(:uuid_namespace), at)
        return nil if value.nil?
        return value if value.match?(UUID)

        fault('idempotency.bad_namespace', at, value: value.inspect)
      end

      def collect_aliases
        seen = {}
        @aliases.each_with_index do |name, index|
          record(seen, name, "#{path('aliases')}[#{index}]")
        end
        check_canonical(seen)
        seen.keys
      end

      def record(seen, name, at)
        key = Normalizer.call(name)
        return fault('idempotency.empty_alias', at, name: name.inspect) if key.empty?
        return duplicate(name, seen[key], at) if seen.key?(key)

        seen[key] = name
      end

      def duplicate(name, other, at)
        fault('idempotency.duplicate_alias', at, name: name.inspect, other: other.inspect)
      end

      def check_canonical(seen)
        return if @canonical_header.nil?
        return if seen.key?(Normalizer.call(@canonical_header))

        fault('idempotency.canonical_missing', path('aliases'), header: @canonical_header.inspect)
      end
    end
  end
end
