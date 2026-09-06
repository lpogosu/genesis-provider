# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Уведомления: подпись и разбор события.
      #
      # Путей два, и оба реальные. Публичный верификатор маршрут вебхука
      # зовёт по сырым байтам до разбора JSON; внутри process_callback подпись
      # проверяется только тогда, когда rules/contract.yml говорит, что байты
      # и заголовки лежат в аргументе колбэка. Негативные фикстуры (заведомо
      # неверная подпись, событие вне enum) обязаны кончиться отказом — иначе
      # чужое уведомление меняло бы статус операции.
      class Callbacks < Base
        SIGNATURE_METHOD = Generators::Service::Signature::PUBLIC_NAME
        INVALID = Generators::Service::Signature::INVALID_CODE

        # @return [Array<Finding>]
        def call
          return [] if spec.nil?

          self.method_name = spec.name
          return [unchecked(nameless, t('run_no_webhook'))] if ctx.webhook.nil?
          return [unchecked(nameless, t('run_no_fixture'))] if all.empty?

          signatures + events
        end

        private

        def spec
          @spec ||= ctx.contract.method_for(:webhook)
        end

        def all
          @all ||= fixtures.notifications
        end

        def nameless
          t('aspect_event', name: '—')
        end

        # Заголовок подписи не выведен — сервис отказывает любому уведомлению,
        # и это не итог прогона, а известный пробел: он уже стоит TODO в коде
        # и пунктом в отчёте.
        def signed?
          parts[:signature].known?(:header)
        end

        # Публичный верификатор: верная подпись обязана дать nil, заведомо
        # неверная — отказ. Значение заголовка в фикстуре посчитано тем же
        # профилем подписи, по которому сгенерирован верификатор.
        def signatures
          previous = method_name
          self.method_name = SIGNATURE_METHOD
          list = all.map { |fixture| signature_finding(fixture) }
          self.method_name = previous
          list
        end

        def signature_finding(fixture)
          aspect = t('aspect_signature', name: fixture['name'])
          return unchecked(aspect, t('run_no_signature_profile')) unless signed?
          return unchecked(aspect, t('run_signature_timestamp')) if timestamped?
          return unchecked(aspect, t('run_no_raw_body')) if fixture['raw_body'].nil?

          result, error = invoke(SIGNATURE_METHOD, fixture['raw_body'], fixture['headers'])
          return crashed(aspect, error) if error

          verify(aspect) { signature_problem(fixture, result) }
        end

        def signature_problem(fixture, result)
          return judge.failure(result, code: expected_code(fixture)) if invalid?(fixture)
          return nil if result.nil?

          t('run_signature_rejected', code: result.code.inspect, key: result.key.inspect)
        end

        # Уведомление целиком: событие обязано дойти до хелпера платформы, а
        # негативная фикстура — до отказа с обещанным кодом.
        def events
          all.map { |fixture| event_finding(fixture) }
        end

        def event_finding(fixture)
          aspect = t('aspect_event', name: fixture['name'])
          problem = skipped(fixture)
          return unchecked(aspect, problem) if problem

          result, error = invoke(spec.name, payload(fixture))
          return crashed(aspect, error) if error

          verify(aspect) { event_problem(fixture, result) }
        end

        # Почему уведомление не прогнать через колбэк: подпись внутри него
        # проверить нечем либо профиль подписи не выведен, и тогда отказ
        # приходит раньше разбора события.
        def skipped(fixture)
          return t('run_no_signature_profile') if unpackable? && !signed?
          return t('run_signature_timestamp') if invalid?(fixture) && timestamped?
          return t('run_no_signature_in_callback') if invalid?(fixture) && !unpackable?

          nil
        end

        def unpackable?
          parts[:signature].unpackable?
        end

        # Профиль Standard Webhooks проверяет допуск метки времени по
        # Time.now, а фикстура подписана фиксированной меткой
        # (SPECGEN_TIMESTAMP): к моменту прогона допуск истёк. Итог такой
        # проверки зависел бы от часов, а не от кода, и отчёт перестал бы
        # быть детерминированным — поэтому подпись здесь не проверяется, а
        # событие разбирается по пути «маршрут сам проверил подпись».
        def timestamped?
          parts[:signature].timestamped?
        end

        def event_problem(fixture, result)
          expected = fixture['expected'] || {}
          internal = expected['internal_status']
          return judge.success(result) || judge.helper(internal) if internal

          judge.failure(result, code: expected['failure_code'], key: expected['error_key'])
        end

        def invalid?(fixture)
          fixture.dig('expected', 'error_key').to_s == "errors.#{INVALID}"
        end

        def expected_code(fixture)
          fixture.dig('expected', 'failure_code')
        end

        # Аргумент колбэка той формы, которую описывает rules/contract.yml:
        # разобранное тело плюс сырые байты и заголовки, если маршрут их
        # передаёт.
        def payload(fixture)
          body = Generators::Fixtures::Values.dup_value(fixture['body'])
          return body if !body.is_a?(Hash) || timestamped?

          add(body, ctx.platform.callback_raw_body, fixture['raw_body'])
          add(body, ctx.platform.callback_headers, fixture['headers'])
          body
        end

        def add(body, expression, value)
          keys = Expression.keys_under(expression, ctx.platform.callback_body)
          return if keys.nil? || value.nil?

          *head, last = keys
          head.reduce(body) { |scope, key| scope[key] ||= {} }[last] = value
        end
      end
    end
  end
end
