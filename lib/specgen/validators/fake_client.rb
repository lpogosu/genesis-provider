# frozen_string_literal: true

module SpecGen
  module Validators
    # HTTP-клиент платформы, подменённый телами из fixtures.json.
    #
    # Сети в прогоне нет и быть не может: генератор — чистая функция от своих
    # файлов, а WebMock в тестах превращает любую попытку выйти наружу в
    # падение. Отвечает клиент тем, что записано в фикстурах: сценарий
    # называет операцию и код ответа, клиент достаёт тело и отдаёт его в том
    # виде, в каком сервис его ждёт, — строкой JSON, потому что
    # сгенерированный parse_json разбирает `response.body`.
    #
    # Интерфейс клиента — допущение того же уровня, что и в шаблоне:
    # client.post(url, payload, headers) и client.get(url, headers), ответ
    # читается как response.status и response.body.
    class FakeClient
      # Методы с телом запроса — те же, что знает презентер HTTP-обмена.
      WITH_BODY = Generators::Service::Http::WITH_BODY
      # Методы без тела. Больше провайдеру взяться неоткуда: их набор задаёт
      # спецификация, а не мы.
      WITHOUT_BODY = %i[get delete head options].freeze

      # Ответ провайдера в том виде, в каком его читает сгенерированный код.
      Response = Struct.new(:status, :body)
      # Один исходящий вызов: метод, адрес, тело и заголовки как есть.
      Call = Struct.new(:verb, :url, :payload, :headers)

      # @return [Array<Call>] вызовы с последнего сброса
      attr_reader :calls

      # @param fixtures [FixtureSet] записанные фикстуры
      def initialize(fixtures)
        @fixtures = fixtures
        @calls = []
        @answer = Response.new(200, '{}')
        define_verbs
      end

      # Чем клиент ответит на следующий вызов.
      # @param operation [String] ключ операции
      # @param status [Integer] код ответа
      # @return [Response]
      def reply(operation:, status:)
        fixture = @fixtures.responses(operation).find { |item| item['status'].to_i == status.to_i }
        body(status, fixture && fixture['body'])
      end

      # Ответ, которого в фикстурах нет: сценарий задаёт его сам.
      # @param status [Integer]
      # @param value [Object] тело как разобранный JSON
      # @return [Response]
      def body(status, value)
        @answer = Response.new(status.to_i, ::JSON.generate(value))
      end

      # @return [void] забыть вызовы прошлого сценария
      def reset
        @calls = []
      end

      private

      # Методы клиента определяются по списку, а не пишутся по одному:
      # спецификация вправе объявить операцию любым методом HTTP, и прогон не
      # должен падать на PATCH только потому, что его забыли перечислить.
      def define_verbs
        WITH_BODY.each do |verb|
          define_singleton_method(verb) do |url, payload = nil, headers = nil|
            record(verb, url, payload, headers)
          end
        end
        WITHOUT_BODY.each do |verb|
          define_singleton_method(verb) { |url, headers = nil| record(verb, url, nil, headers) }
        end
      end

      # @return [Response] заготовленный ответ
      def record(verb, url, payload, headers)
        @calls << Call.new(verb, url, payload, headers)
        @answer
      end
    end
  end
end
