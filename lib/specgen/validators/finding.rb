# frozen_string_literal: true

module SpecGen
  module Validators
    # Одна проверка одного тела из fixtures.json против схемы спецификации.
    #
    #   kind       :passed | :failed | :synthesized | :unchecked
    #   subject    что проверяли: «запрос createPayout»
    #   json_path  место схемы в спецификации, "$.paths['/payouts'].post…"
    #   message    что не так; у прошедшей проверки nil
    #
    # Видов четыре, потому что «не прошло» бывает трёх разных смыслов.
    # `failed` — тело взято из `examples` спецификации дословно и не проходит
    # её же схему: это расхождение спецификации с самой собой либо наша
    # ошибка сборки, и то и другое надо читать глазами. `synthesized` — тело
    # собрано нами по типам (или намеренно негативно, как уведомление с
    # незнакомым событием), и несовпадение с `pattern` или `enum` законно.
    # `unchecked` — схемы в спецификации нет, проверять не с чем.
    Finding = Struct.new(:kind, :subject, :json_path, :message, keyword_init: true)

    # Проверки и предикаты Finding.
    class Finding
      KINDS = %i[passed failed synthesized unchecked].freeze

      # @param kind [Symbol] один из KINDS
      # @param subject [String]
      # @param json_path [String, nil]
      # @param message [String, nil]
      # @raise [ArgumentError]
      def initialize(kind:, subject:, json_path: nil, message: nil)
        unless KINDS.include?(kind)
          raise ArgumentError, "вид проверки: ожидается один из #{KINDS.inspect}, " \
                               "получено #{kind.inspect}"
        end

        super
      end

      # @return [Boolean]
      def passed?
        kind == :passed
      end

      # @return [Boolean] о находке нужно рассказать в отчёте
      def problem?
        !passed?
      end
    end
  end
end
