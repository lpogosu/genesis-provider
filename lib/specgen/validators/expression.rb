# frozen_string_literal: true

module SpecGen
  module Validators
    # Выражения платформы из rules/contract.yml, прочитанные в обратную
    # сторону.
    #
    # Сгенерированный сервис читает данные платформы выражениями, которые
    # шаблон подставил как есть: `operation.amount`,
    # `operation.payout_requisite.dig('способ', 'поле')`, `payload['raw_body']`.
    # Чтобы вызвать этот сервис, прогону нужен объект операции и аргумент
    # колбэка ровно той формы, которую эти выражения читают, — то есть тот же
    # справочник, прочитанный наоборот. Разбор здесь, а не в вызывающем: иначе
    # два места знали бы форму выражений и разошлись бы при первой правке
    # контракта.
    #
    # Ничего, кроме доступа к атрибуту и цепочки ключей хеша, разбирать не
    # нужно: контракт описывает данные, а не вычисления. Выражение сложнее
    # (вызов метода, интерполяция) даёт nil, и прогон честно скажет, что
    # проверить эту роль нечем.
    module Expression
      # operation.amount — чтение поля объекта операции.
      ATTRIBUTE = /\A([a-z_][A-Za-z_0-9]*)\.([a-z_][A-Za-z_0-9]*)\z/
      # …['ключ'] на конце выражения, сколько угодно раз.
      BRACKET = /\A(?<receiver>.+)\[(?<quote>['"])(?<key>[^'"]*)\k<quote>\]\z/
      # …dig('a', 'b') на конце выражения.
      DIG = /\A(?<receiver>.+?)\.dig\((?<args>[^()]*)\)\z/
      STRING = /\A(['"])(.*)\1\z/

      # @param text [String, nil] выражение вида "operation.amount"
      # @return [Array(String, String), nil] приёмник и имя поля
      def self.attribute(text)
        found = text.to_s.strip.match(ATTRIBUTE)
        found && [found[1], found[2]]
      end

      # Цепочка ключей хеша на конце выражения.
      #
      # @param text [String, nil] "operation.payout_requisite.dig('a', 'b')"
      # @return [Array(String, Array<String>), nil] приёмник и путь ключей
      def self.path(text)
        rest = text.to_s.strip
        dig = rest.match(DIG)
        return [dig[:receiver], strings(dig[:args])] if dig

        keys = []
        while (found = rest.match(BRACKET))
          keys.unshift(found[:key])
          rest = found[:receiver]
        end
        keys.empty? ? nil : [rest, keys]
      end

      # Путь ключей относительно известного приёмника.
      #
      # @param text [String, nil] выражение
      # @param receiver [String, nil] выражение приёмника, например
      #   "operation.payout_requisite"
      # @return [Array<String>, nil] nil, если приёмник другой
      def self.keys_under(text, receiver)
        found = path(text)
        return nil if found.nil? || receiver.nil? || found.first != receiver.to_s.strip

        found.last
      end

      # @param args [String] аргументы dig как текст
      # @return [Array<String>] только строковые литералы
      def self.strings(args)
        args.split(',').map(&:strip).filter_map { |item| item[STRING, 2] }
      end
    end
  end
end
