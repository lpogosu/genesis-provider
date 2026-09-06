# frozen_string_literal: true

module SpecGen
  module Validators
    # Изолированная загрузка сгенерированного сервиса.
    #
    # Класс исполняется в анонимном модуле: `Module#module_eval` с именем
    # файла даёт настоящие номера строк в сообщениях об ошибках, а константы
    # остаются внутри модуля и исчезают вместе с ним. Ни один класс прогона не
    # попадает в Object, поэтому два прогона подряд не видят друг друга, а
    # `Provider::BaseService` соседнего процесса — тем более.
    #
    # Перед загрузкой в модуль кладётся подмена платформы под тем именем,
    # которое назвал справочник (`base_class` в rules/contract.yml): сервис
    # наследует от неё, не зная, что она подменена.
    class Sandbox
      # @return [Platform] подмена платформы: у неё записаны вызовы хелперов
      attr_reader :platform
      # @return [StandardError, SyntaxError, nil] чем закончилась загрузка
      attr_reader :error

      # @param source [String] текст сгенерированного класса
      # @param path [String] путь к файлу, для номеров строк в ошибках
      # @param class_name [String] полное имя класса сервиса
      # @param base_class [String] полное имя базового класса платформы
      # @param platform [Platform] подмена платформы
      # @param env [Hash{String => String}] переменные окружения на время
      #   загрузки: адрес провайдера сервис читает из ENV с умолчанием, и
      #   чужое значение в окружении разработчика меняло бы прогон
      # @param stubs [Hash{String => Object}] методы, которые генератор
      #   оставил человеку и которые на время прогона отвечают заглушкой
      def initialize(source:, path:, class_name:, base_class:, platform:, env: {}, stubs: {})
        @source = source
        @path = path
        @class_name = class_name
        @base_class = base_class
        @platform = platform
        @env = env
        @stubs = stubs
        load!
      end

      # @return [Object, nil] экземпляр сгенерированного класса
      attr_reader :service

      # @return [Boolean] класс загрузился и создался
      def loaded?
        !@service.nil?
      end

      # @param name [String, Symbol] имя константы сервиса
      # @return [Object, nil] nil, если константы нет
      def constant(name)
        klass = @service&.class
        klass&.const_defined?(name, false) ? klass.const_get(name, false) : nil
      end

      private

      def load!
        @module = Module.new
        install(@base_class, @platform.base_class)
        with_env { @module.module_eval(@source, @path) }
        @service = found_class.new
        install_stubs
      rescue StandardError, ScriptError => e
        @error = e
      end

      # Метод, который генератор честно оставил человеку (получение токена
      # OAuth2, подпись запроса по HMAC), поднимает NotImplementedError на
      # первом же запросе. На время прогона он отвечает очевидно ненастоящим
      # значением: иначе у такого провайдера проверялась бы одна загрузка.
      def install_stubs
        @stubs.each do |name, value|
          next unless @service.respond_to?(name, true)

          @service.singleton_class.define_method(name) { |*| value }
        end
      end

      # Класс ищется по полному имени, а если его там нет — по короткому в
      # пространствах имён первого уровня: пространство имён печатает шаблон,
      # а полное имя складывает контракт, и разойтись они вправе.
      def found_class
        found = dig(@class_name.to_s.split('::')) || search(@class_name.to_s.split('::').last)
        return found if found.is_a?(Class)

        raise ValidationError.new(t('run_no_class', name: @class_name), file: @path)
      end

      # Константа под составным именем: пространства имён создаются классами,
      # потому что сгенерированный файл открывает их словом `class`.
      def install(name, value)
        *namespaces, last = name.to_s.split('::')
        owner = namespaces.reduce(@module) do |scope, part|
          scope.const_defined?(part, false) ? scope.const_get(part, false) : nest(scope, part)
        end
        owner.const_set(last, value)
      end

      def nest(scope, part)
        scope.const_set(part, Class.new)
      end

      # @param path [Array<String>] части имени
      # @return [Object, nil]
      def dig(path)
        path.reduce(@module) { |scope, part| scope.const_get(part, false) }
      rescue NameError
        nil
      end

      # @param short [String] имя класса без пространства имён
      # @return [Class, nil]
      def search(short)
        scopes = [@module, *@module.constants.map { |name| @module.const_get(name, false) }]
        owner = scopes.find do |scope|
          scope.is_a?(Module) && scope.const_defined?(short, false)
        end
        owner&.const_get(short, false)
      end

      def t(key, **params)
        Texts.t("validators.#{key}", **params)
      end

      # Переменные окружения выставляются только на время загрузки и
      # возвращаются как были — даже если загрузка бросила исключение.
      def with_env
        saved = @env.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
        @env.each { |key, value| ENV[key] = value }
        yield
      ensure
        saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end
  end
end
