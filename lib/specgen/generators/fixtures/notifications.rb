# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Входящие уведомления: по фикстуре на каждое событие из enum, плюс две
      # негативные — заведомо неверная подпись и незнакомое событие.
      #
      # Подпись считается по-настоящему: HMAC от точных байтов raw_body
      # секретом-заглушкой из credentials по профилю подписи из IR. Фикстуру
      # можно передать в process_callback как есть и получить success.
      class Notifications < Base
        # Имя незнакомого события: суффикс к префиксу известного, чтобы оно
        # заведомо не попало в enum.
        UNKNOWN_SUFFIX = 'unknown'
        UNKNOWN_EVENT = 'unknown_event'
        # Причины отказа негативных фикстур — те же, что печатает
        # сгенерированный сервис ключом локализации; код платформы к ним
        # берётся из rules/contract.yml.
        INVALID_SIGNATURE_REASON = Service::Signature::INVALID_CODE
        UNKNOWN_EVENT_REASON = Service::Callback::UNKNOWN_EVENT_CODE

        # @return [Array<Hash>] фикстуры событий, затем негативные
        def all
          return [] if webhook.nil? || events.empty?

          list = events.map { |event| fixture(event) }
          base = base_of(list)
          list << invalid_signature(base) if signing.known?
          list << unknown_event(base)
          list
        end

        private

        def webhook
          ctx.webhook
        end

        # Негативные фикстуры строятся на настоящем примере спецификации,
        # если он есть: неверна в них должна быть ровно одна вещь.
        def base_of(list)
          list.find { |item| item['source'] == SPEC_EXAMPLE } || list.first
        end

        # @return [Array<IR::WebhookEvent>] те же события и в том же порядке,
        #   что в константе EVENT_MAP сервиса
        def events
          parts[:tables].events
        end

        def fixture(event)
          body = body_for(event)
          raw = ::JSON.generate(body.value)
          notes = []
          notes << t('event_unmapped', event: event.name) unless event.mapped?
          notes << t('signature_absent') unless signing.known?
          { 'name' => "webhook #{event.name}", 'event' => event.name,
            'headers' => headers(raw), 'raw_body' => raw, 'body' => body.value,
            'expected' => { 'internal_status' => internal_status(event) } }
            .merge(tail(body, notes))
        end

        def internal_status(event)
          event.mapped? ? event.internal_status.value.to_s : nil
        end

        def headers(raw, valid: true)
          { CONTENT_TYPE => IR::Operation::JSON }.merge(signing.headers(raw, valid: valid))
                                                 .sort.to_h
        end

        # Тело события: свой пример, иначе пример соседнего события с
        # подставленными именем события и статусом, иначе сборка по схеме.
        def body_for(event)
          return spec_body(IR::Response::DEFAULT_EXAMPLE, event.example) unless event.example.nil?

          borrowed(event) || substitute(schema_body(event), event)
        end

        def schema_body(event)
          body_from({}, webhook.schema, t('no_event_example', event: event.name), expected: true)
        end

        # Тело уведомления в спецификации одно на все события: отличаются в
        # нём поле события и статус, их и подставляем.
        def borrowed(event)
          examples = webhook_operation&.request_examples || {}
          return nil if examples.empty?

          substitute(Body.new(value: Values.dup_value(examples.values.first),
                              source: SCHEMA_EXAMPLE,
                              notes: [t('no_event_example', event: event.name)]), event)
        end

        def webhook_operation
          webhook.operation && ctx.profile.operation(webhook.operation)
        end

        # Подставляются только значения, названные самой спецификацией (enum
        # события и статуса): заглушек это не добавляет.
        def substitute(body, event)
          Values.assign(body.value, event_path, event.name)
          Values.assign(body.value, status_path, event.provider_status) if event.provider_status
          body
        end

        def event_path
          field = parts[:callback].event_field
          field && [field.name]
        end

        def status_path
          ctx.role_path(webhook.schema, :status)
        end

        # Негативная фикстура: тело настоящее, подпись заведомо неверна.
        def invalid_signature(base)
          negative(base, INVALID_SIGNATURE_REASON, base['event'], t('negative_signature'))
            .merge('headers' => headers(base['raw_body'], valid: false))
        end

        # Негативная фикстура: подпись верна, событие не объявлено в enum.
        def unknown_event(base)
          value = Values.dup_value(base['body'])
          name = unknown_name(base['event'])
          Values.assign(value, event_path, name)
          raw = ::JSON.generate(value)
          negative(base, UNKNOWN_EVENT_REASON, name, t('negative_event'))
            .merge('headers' => headers(raw), 'raw_body' => raw, 'body' => value)
        end

        # Ожидаемое от process_callback: код платформы первым аргументом
        # failure и ключ локализации вторым — оба проверяет тест.
        def negative(base, reason, event, note)
          expected = { 'failure_code' => ctx.platform.failure_codes.internal(reason).to_s,
                       'error_key' => "errors.#{reason}" }
          { 'name' => "webhook #{reason}", 'event' => event, 'headers' => base['headers'],
            'raw_body' => base['raw_body'], 'body' => base['body'],
            'expected' => expected, 'source' => SYNTHESIZED, '_todo' => note }
        end

        def unknown_name(known)
          prefix = known.to_s.rpartition('.').first
          prefix.empty? ? UNKNOWN_EVENT : "#{prefix}.#{UNKNOWN_SUFFIX}"
        end
      end
    end
  end
end
