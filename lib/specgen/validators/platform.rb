# frozen_string_literal: true

module SpecGen
  module Validators
    # Подмена платформы: базовый класс, от которого наследует сгенерированный
    # сервис на время прогона.
    #
    # Настоящего базового класса нам не выдали (эксперты кейса: его
    # реализация несущественна, «базовый класс-фабрика»), поэтому подмена
    # собирается из того же справочника, которым сгенерирован сервис:
    # rules/contract.yml называет хелперы, методы, вызывающие `super`, и
    # предикат успешного результата. Ни одного имени метода здесь не написано
    # литералом — иначе переименованный в справочнике хелпер ломал бы прогон,
    # а не проверялся им.
    #
    # Всё, что сервис зовёт у платформы, записывается: по списку вызовов
    # видно, перевёл ли класс статус в тот хелпер, который обещает
    # INTEGRATION.md.
    class Platform
      # Имя объекта с учётными данными и метода, который их отдаёт. Приходят
      # они не из контракта, а из выражения, которое печатает презентер
      # авторизации, — там же живёт правило «секреты только через credentials».
      HOLDER, SECRETS = Generators::Service::Authorization::CREDENTIALS.split('.')
      EMPTY_HEADERS = {}.freeze

      # Держатель секретов: сервис читает их как provider.credentials[ключ].
      Account = Struct.new(SECRETS.to_sym)
      # Один вызов хелпера платформы: имя и аргументы как есть.
      Call = Struct.new(:name, :args)
      # Результат хелпера успеха или отказа. Форма — из описания кейса:
      # платформа ветвится по коду, а сообщение берёт из ключа локализации.
      Outcome = Struct.new(:kind, :code, :key, :result) do
        # @return [Boolean]
        def success?
          kind == :success
        end
      end

      # @return [Array<Call>] вызовы хелперов с последнего сброса
      attr_reader :calls
      # @return [FakeClient]
      attr_reader :client
      # @return [Account]
      attr_reader :account

      # @param contract [Rules::ContractBook]
      # @param credentials [Hash] учётные данные-заглушки из fixtures.json
      # @param client [FakeClient]
      def initialize(contract:, credentials:, client:)
        @contract = contract
        @account = Account.new(credentials)
        @client = client
        @calls = []
        @outcome = outcome_class
      end

      # @return [Class] анонимный класс, который встаёт на место базового
      def base_class
        @base_class ||= build
      end

      # @return [void] забыть вызовы прошлого сценария
      def reset
        @calls = []
      end

      # @param name [String, nil] имя хелпера
      # @return [Array<Call>]
      def calls_of(name)
        @calls.select { |call| call.name == name }
      end

      # Хелперы смены статуса, вызванные с последнего сброса, по порядку.
      # @return [Array<String>]
      def status_calls
        @calls.map(&:name) & status_helpers
      end

      # @return [Array<String>] имена хелперов, которые меняют статус операции
      def status_helpers
        @contract.internal_statuses.filter_map { |status| @contract.helper_for_status(status) }
      end

      # Методы контракта, у которых сгенерированный сервис зовёт `super`:
      # подмена обязана ответить на них успехом, иначе предпроверки
      # останавливаются на первой же строке.
      # @return [Array<String>] имена методов
      def super_methods
        @contract.method_names.map { |name| @contract.method_spec(name) }
                 .select(&:calls_super?).map(&:name)
      end

      # Хелперы, у которых от подмены нужна только запись вызова: смена
      # статуса операции и методы контракта, у которых сервис зовёт `super`.
      # @return [Array<String>]
      def recorded
        status_helpers + super_methods
      end

      # @param name [String] имя хелпера
      # @param args [Array] аргументы вызова
      # @return [Outcome] успешный результат
      def note(name, args)
        @calls << Call.new(name, args)
        @outcome.new(:success, nil, nil, nil)
      end

      # @param result [Hash] именованные аргументы хелпера успеха
      # @return [Outcome]
      def accept(result)
        @calls << Call.new(@contract.helper(:success), [result])
        @outcome.new(:success, nil, nil, result)
      end

      # @param code [Symbol] код платформы
      # @param key [String] ключ локализации
      # @return [Outcome]
      def decline(code, key)
        @calls << Call.new(@contract.helper(:failure), [code, key])
        @outcome.new(:failure, code, key, nil)
      end

      private

      # Предикат успеха назван контрактом, поэтому и подмена отвечает тем
      # именем, которое напечатано в сгенерированном методе предпроверок.
      def outcome_class
        predicate = @contract.platform.success_predicate
        return Outcome if predicate.nil? || predicate == 'success?'

        Class.new(Outcome) { define_method(predicate) { success? } }
      end

      def build
        platform = self
        contract = @contract
        Class.new do
          define_method(HOLDER) { platform.account }
          define_method(contract.helper(:client)) { platform.client }
          define_method(contract.helper(:auth_headers)) { EMPTY_HEADERS }
          define_method(contract.helper(:success)) { |**rest| platform.accept(rest) }
          define_method(contract.helper(:failure)) { |code, key = nil| platform.decline(code, key) }
          platform.recorded.each do |name|
            define_method(name) { |*args| platform.note(name, args) }
          end
        end
      end
    end
  end
end
