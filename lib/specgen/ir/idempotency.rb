# frozen_string_literal: true

module SpecGen
  module IR
    # Поддержка Idempotency-Key у провайдера и то, как сгенерированный сервис
    # получает ключ. В спецификации заголовок может быть необязательным;
    # сервис отправляет его всегда, когда ключ известен.
    #
    #   header      Derived<String> — имя заголовка, например "Idempotency-Key"
    #   strategy    Derived<Symbol>, одна из STRATEGIES
    #   required    помечает ли спецификация заголовок обязательным
    #   operations  Operation#key каждой операции, принимающей заголовок
    #   json_path   где объявлен параметр-заголовок
    Idempotency = Struct.new(:header, :strategy, :required, :operations, :json_path,
                             keyword_init: true)

    # Словарь значений и значения по умолчанию Idempotency.
    class Idempotency
      include Node

      # uuid_v5: детерминированный UUID от operation.id, поэтому повторы
      # дедуплицируются; external_id: отправить ключом собственный
      # идентификатор операции платформы; none: провайдер идемпотентности не
      # предлагает.
      STRATEGIES = %i[uuid_v5 external_id none].freeze
      UNDERIVED = 'не выведено'

      # @param header [Derived]
      # @param strategy [Derived]
      # @param required [Boolean]
      # @param operations [Array<String>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(header: Derived.unknown(evidence: UNDERIVED),
                     strategy: Derived.unknown(evidence: UNDERIVED), required: false,
                     operations: [], json_path: nil)
        Node.assert_derived!(header, 'заголовок идемпотентности')
        Node.assert_derived!(strategy, 'стратегия идемпотентности', allowed: STRATEGIES)
        super
      end

      # @return [Boolean] сервис может отправить ключ
      def supported?
        header.known? && strategy.known? && strategy.value != :none
      end
    end
  end
end
