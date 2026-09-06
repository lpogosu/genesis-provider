# frozen_string_literal: true

module SpecGen
  module Validators
    # Прогон собранного класса на его же фикстурах.
    #
    # Сверка фикстур со схемами (FixtureCheck) доказывает, что запрос
    # правильной формы. Она не доказывает, что класс, который его собирает,
    # хотя бы загружается. Эксперты кейса оценивают именно сгенерированный
    # класс и живого трафика не требуют — значит, единственный способ показать,
    # что класс работает, это исполнить его без сети: подменить базовый класс
    # платформы и HTTP-клиент, вызвать все четыре метода контракта и методы
    # операций вне контракта на фикстурах и посмотреть, что он делает.
    #
    # Что доказывается прогоном: класс загружается и создаётся; зовёт клиента
    # по адресу и методу своей операции; отправляет заголовок авторизации со
    # значением из учётных данных и детерминированный ключ идемпотентности;
    # собирает тело запроса, совпадающее с примером спецификации; читает
    # идентификатор из ответа и отдаёт его платформе; переводит каждый статус и
    # каждое событие в тот хелпер, который обещает INTEGRATION.md; отвечает
    # объявленным кодом отказа на каждый код ошибки и отвергает уведомление с
    # неверной подписью.
    #
    # Чего прогон не делает: не выходит в сеть (клиент подменён), не блокирует
    # генерацию (файлы уже записаны) и не бросает исключений — упавший вызов
    # становится находкой «не проверено» с текстом ошибки.
    class ServiceCheck
      # Виды находок прогона: синтезированного тела здесь не бывает, вызов
      # либо сошёлся, либо нет, либо его нечем было сделать.
      KINDS = %i[passed failed unchecked].freeze
      # Порядок сценариев фиксирован: он же порядок находок в отчёте.
      SCENARIOS = [Run::Prechecks, Run::Creation, Run::Polling, Run::Callbacks,
                   Run::Extras].freeze

      # Всё, что нужно сценарию: загруженный сервис, подмены и презентеры, по
      # которым видно, что именно сгенерировано.
      Runtime = Struct.new(:sandbox, :platform, :client, :fixtures, :ctx, :parts, :payment,
                           :judge, keyword_init: true)

      # @param profile [IR::ProviderProfile]
      # @param rules [Rules::Registry]
      # @param service_file [String] путь к записанному service.rb
      # @param fixtures_file [String] путь к записанному fixtures.json
      def initialize(profile:, rules:, service_file:, fixtures_file:)
        @profile = profile
        @rules = rules
        @service_file = service_file
        @fixtures_file = fixtures_file
      end

      # @return [Result]
      def call
        runtime = build
        loaded = load_finding(runtime)
        return Result.new([loaded]) unless runtime.sandbox.loaded?

        Result.new([loaded, *SCENARIOS.flat_map { |scenario| scenario.new(runtime).call }])
      rescue StandardError, ScriptError => e
        Result.new([broken(e)])
      end

      private

      def build
        view = Generators::Service::View.new(profile: @profile, rules: @rules, naming: naming)
        fixtures = FixtureSet.new(@fixtures_file)
        client = FakeClient.new(fixtures)
        platform = Platform.new(contract: contract, credentials: fixtures.credentials,
                                client: client)
        Runtime.new(sandbox: sandbox(view, platform, fixtures.base_url),
                    platform: platform, client: client, fixtures: fixtures, ctx: view.context,
                    parts: view.parts, payment: payment(view, fixtures),
                    judge: judge(client, platform, fixtures))
      end

      def naming
        Generators::Naming.for(@profile)
      end

      def contract
        @rules.contract
      end

      def payment(view, fixtures)
        Payment.new(ctx: view.context, parts: view.parts, fixtures: fixtures)
      end

      def judge(client, platform, fixtures)
        Run::Judge.new(client: client, platform: platform, contract: contract,
                       base_url: fixtures.base_url)
      end

      # Адрес провайдера сервис читает из переменной окружения с умолчанием из
      # спецификации. На время прогона переменная выставляется в тот же адрес,
      # с которым собраны фикстуры: иначе значение из окружения разработчика
      # меняло бы результат проверки.
      def sandbox(view, platform, base_url)
        ctx = view.context
        Sandbox.new(source: File.read(@service_file, encoding: 'UTF-8'), path: @service_file,
                    class_name: ctx.full_class_name, base_class: contract.base_class,
                    platform: platform, stubs: auth_stubs(view.parts),
                    env: base_url.nil? ? {} : { ctx.base_url_env => base_url })
      end

      # Заглушки, которые генератор оставил человеку: получение токена OAuth2,
      # подпись запроса по HMAC. Значение — то же очевидно ненастоящее, что и
      # в фикстурах; без него класс с таким типом авторизации не доходит ни до
      # одного запроса.
      def auth_stubs(parts)
        name = parts[:authorization].stub_name
        name.nil? ? {} : { name => "#{Generators::Fixtures::Base::STUB_PREFIX}#{name}" }
      end

      def load_finding(runtime)
        subject = Texts.t('validators.run_subject_load', name: runtime.ctx.full_class_name)
        return Finding.new(kind: :passed, subject: subject) if runtime.sandbox.loaded?

        Finding.new(kind: :failed, subject: subject, message: describe(runtime.sandbox.error))
      end

      def broken(error)
        Finding.new(kind: :unchecked, subject: Texts.t('validators.run_subject_stage'),
                    message: describe(error))
      end

      def describe(error)
        return '' if error.nil?
        return error.message if error.is_a?(SpecGen::Error)

        Texts.t('validators.run_exception', error: "#{error.class}: #{error.message}")
      end
    end
  end
end
