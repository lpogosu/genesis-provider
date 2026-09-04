# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Что получает каждый анализатор и как он запускается.
    #
    # Четыре входа одни и те же везде: разрешённый `document`, заполняемый
    # `profile`, справочники `rules` и опции CLI `options`. Подклассы
    # реализуют только `#call` и ничего из этой обвязки, поэтому новый
    # анализатор — это один файл и одна строка в analyzers.rb.
    #
    # Здешние хелперы — те, без которых предупреждение анализатора нельзя
    # исправить: JSONPath, указывающий на тот самый элемент спецификации, из
    # которого взялось решение, и в той же нотации, которой OpenAPI Overlay
    # адресует свои target'ы, — так предупреждение и его исправление
    # указывают на одно место.
    class Base
      # Фиксированные поля Path Item Object, которые являются операциями
      # (OpenAPI 3).
      HTTP_METHODS = Operations::HTTP_METHODS

      # Создаёт анализатор и запускает его; принимает то же, что #initialize.
      # @return [Object] то, что вернул #call анализатора
      def self.call(**)
        new(**).call
      end

      # @param document [SpecLoader::Document] спецификация со всеми
      #   разрешёнными `$ref`
      # @param profile [IR::ProviderProfile] профиль, который заполняем
      # @param rules [Rules::Registry, nil] справочники; явный nil для
      #   анализатора, который не читает ни одного
      # @param options [Hash] опции CLI, ключи строками или символами
      def initialize(document:, profile:, rules:, options: {})
        @document = document
        @profile = profile
        @rules = rules
        @options = options || {}
      end

      # Читает документ и заполняет свою часть профиля.
      # @return [IR::ProviderProfile]
      # @raise [NotImplementedError] всегда; подклассы переопределяют метод
      def call
        raise NotImplementedError, "#{self.class} обязан реализовать #call"
      end

      protected

      # @return [SpecLoader::Document]
      attr_reader :document
      # @return [IR::ProviderProfile]
      attr_reader :profile
      # @return [Rules::Registry, nil]
      attr_reader :rules
      # @return [Hash]
      attr_reader :options

      # Разрешённый документ. Пустой, если корень не является отображением:
      # анализатор никогда не падает на входе, который пропустил загрузчик.
      # @return [Hash]
      def data
        document.data.is_a?(Hash) ? document.data : {}
      end

      # @param keys [Array<String, Integer>] путь ключей от корня документа
      # @return [String] например "$.servers[0].url"
      def json_path(*keys)
        SpecLoader::JsonPath.build(keys)
      end

      # Все операции документа в том порядке, в котором их объявляет файл.
      # Path item и операции неверной формы пропускаются: загрузчик
      # гарантирует, что `paths` есть, а не что каждый его угол — объект.
      # @yieldparam path [String] шаблон, например "/payouts/{id}"
      # @yieldparam http_method [String] в нижнем регистре, один из HTTP_METHODS
      # @yieldparam operation [Hash] Operation Object
      # @return [Enumerator] если вызван без блока
      def each_operation(&)
        return enum_for(:each_operation) unless block_given?

        Operations.each(data, &)
      end

      # Ключ операции — тот же, которым её называют OperationAnalyzer,
      # SchemaNaming и остальной IR.
      # @param path [String]
      # @param http_method [String]
      # @param operation [Hash]
      # @return [String] operationId или "post_payouts"
      def operation_key(path, http_method, operation)
        SchemaNaming.operation_key(operation['operationId'], http_method, path)
      end

      # Роль операции, пересчитанная от документа тем же композитным матчером,
      # что у OperationAnalyzer, — общий компонент, а не чтение чужого
      # результата: анализаторы независимы.
      # @param path [String]
      # @param http_method [String]
      # @param operation [Hash]
      # @return [Symbol] одна из IR::Roles::OPERATION
      def role_of(path, http_method, operation)
        security = operation['security']
        tags = operation['tags'].is_a?(Array) ? operation['tags'].grep(String) : []
        OperationRole.new(book: rules.operations, id: operation['operationId'],
                          http_method: http_method.to_sym, path: path, tags: tags,
                          body: operation['requestBody'].is_a?(Hash),
                          secured: !(security.is_a?(Array) && security.empty?)).call.role
      end

      # Из тестов опции приходят с ключами-символами, из Thor — со строками;
      # анализатор не обязан знать, с какими именно.
      # @param name [Symbol]
      # @return [Object, nil]
      def option(name)
        options.key?(name) ? options[name] : options[name.to_s]
      end
    end
  end
end
