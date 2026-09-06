# frozen_string_literal: true

module SpecGen
  module Validators
    # Сценарии прогона: по классу на метод контракта. Каждый вызывает
    # загруженный сервис на фикстурах и превращает расхождения в находки.
    module Run
      # Общее для сценариев: доступ к загруженному сервису и его окружению,
      # безопасный вызов и три способа закончить проверку.
      #
      # Ни один сценарий не выпускает исключение наружу: упавший вызов — это
      # находка «не проверено» с текстом ошибки, а не падение стадии. Стадия
      # проверки сообщает, а не отменяет: артефакты уже записаны.
      class Base
        # @param runtime [ServiceCheck::Runtime] загруженный сервис и его окружение
        def initialize(runtime)
          @run = runtime
        end

        # @return [Array<Finding>]
        def call
          raise NotImplementedError
        end

        private

        attr_reader :run

        def service
          run.sandbox.service
        end

        def client
          run.client
        end

        def platform
          run.platform
        end

        def ctx
          run.ctx
        end

        def parts
          run.parts
        end

        def fixtures
          run.fixtures
        end

        def judge
          run.judge
        end

        def operation
          run.payment.operation
        end

        # Имя метода сервиса, о котором говорит сценарий: оно стоит в каждой
        # находке, чтобы по отчёту было видно, что именно не сошлось. У
        # операций вне контракта имя приходит от самой операции, поэтому это
        # значение, а не константа класса.
        # @return [String]
        attr_accessor :method_name

        # Вызов метода сервиса с чистого листа: записи прошлого сценария
        # сбрасываются, исключение возвращается вместо результата.
        # Ловится и ScriptError: сгенерированная заглушка OAuth2 честно
        # поднимает NotImplementedError, а это не StandardError. Для прогона
        # это такой же ответ класса, как любой другой, и падать стадии из-за
        # него нельзя.
        #
        # @param name [String] имя метода
        # @param args [Array] аргументы
        # @return [Array(Object, Exception)] результат и ошибка
        def invoke(name, *)
          platform.reset
          client.reset
          return [nil, missing(name)] unless service.respond_to?(name)

          [service.public_send(name, *), nil]
        rescue StandardError, ScriptError => e
          [nil, e]
        end

        def missing(name)
          ValidationError.new(t('run_no_method', method: name))
        end

        # Проверка, чей итог — сообщение о расхождении либо nil.
        # @param aspect [String] что проверяли
        # @return [Finding]
        def verify(aspect)
          problem = yield
          problem.nil? ? passed(aspect) : failed(aspect, problem)
        end

        # @return [Finding]
        def passed(aspect)
          Finding.new(kind: :passed, subject: subject(aspect))
        end

        # @return [Finding]
        def failed(aspect, message)
          Finding.new(kind: :failed, subject: subject(aspect), message: message)
        end

        # @return [Finding]
        def unchecked(aspect, message)
          Finding.new(kind: :unchecked, subject: subject(aspect), message: message)
        end

        # Находка о вызове, который бросил исключение.
        # @return [Finding]
        def crashed(aspect, error)
          unchecked(aspect, t('run_exception', error: "#{error.class}: #{error.message}"))
        end

        def subject(aspect)
          t('run_subject', method: method_name, aspect: aspect)
        end

        # Аргументы метода контракта в объявленном порядке: объект операции
        # туда, где контракт назвал операцию, значение способа выплаты —
        # во все остальные.
        # @param spec [Rules::MethodSpec]
        # @param target [Object] объект операции для этого вызова
        # @return [Array]
        def contract_args(spec, target = operation)
          spec.params.map do |param|
            param[:name] == run.payment.root ? target : run.payment.request_method
          end
        end

        def t(key, **params)
          Texts.t("validators.#{key}", **params)
        end
      end
    end
  end
end
