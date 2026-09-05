# frozen_string_literal: true

module SpecGen
  module Validators
    # Сверка записанного fixtures.json со схемами той же спецификации:
    # запрос — против схемы тела своей операции, ответ — против схемы своего
    # кода, уведомление — против схемы тела вебхука.
    #
    # Читается именно записанный файл, а не то, что генератор держал в
    # памяти: проверять надо артефакт, который увидит человек.
    class FixtureCheck
      # Значение ключа `source`, при котором тело взято из `examples`
      # спецификации дословно; всё остальное собрано нами.
      SPEC_EXAMPLE = Generators::Fixtures::Base::SPEC_EXAMPLE

      # @param document [SpecLoader::Document]
      # @param profile [IR::ProviderProfile]
      # @param fixtures_file [String] путь к записанному fixtures.json
      # @raise [ValidationError] файл артефакта не читается как JSON
      def initialize(document:, profile:, fixtures_file:)
        @profile = profile
        @file = fixtures_file
        @fixtures = read(fixtures_file)
        @targets = Targets.new(document: document, profile: profile)
        @schemas = Schemas.new(document)
      end

      # @return [Result]
      def call
        Result.new(requests + responses + notifications)
      end

      private

      def read(file)
        ::JSON.parse(File.read(file, encoding: 'UTF-8'))
      rescue ::JSON::ParserError, SystemCallError => e
        raise ValidationError.new(t('fixtures_unreadable', error: e.message), file: file)
      end

      def requests
        list('requests').filter_map do |fixture|
          operation = @targets.operation(fixture['name'])
          next if operation.nil?

          verify(fixture, subject(:request, fixture['name']),
                 @targets.request(operation), operation.json_path)
        end
      end

      def responses
        list('responses').filter_map do |fixture|
          operation = @targets.operation(fixture['operation'])
          response = operation && response_of(operation, fixture['status'])
          next if response.nil?

          verify(fixture, subject(:response, fixture['name']),
                 @targets.response(operation, response), response.json_path)
        end
      end

      # Уведомления проверяются схемой того же вебхука, по которому
      # сгенерированы: фикстуры собирает первый вебхук профиля.
      def notifications
        webhook = @profile.webhooks.first
        return [] if webhook.nil?

        keys = @targets.notification(webhook)
        list('notifications').filter_map do |fixture|
          verify(fixture, subject(:notification, fixture['name']), keys, webhook.json_path)
        end
      end

      def list(key)
        value = @fixtures[key]
        value.is_a?(Array) ? value : []
      end

      def response_of(operation, status)
        operation.responses.find { |item| (item.code || item.status).to_s == status.to_s }
      end

      # Исключение валидатора наружу не выходит: любая его неудача — это
      # «проверить нечем», а не отказ генерации. Файлы уже записаны, и
      # стадия сообщает, а не отменяет.
      def verify(fixture, subject, keys, fallback_path)
        path = keys ? SpecLoader::JsonPath.build(keys) : fallback_path
        return absent(fixture, subject, path) if fixture['body'].nil?

        schema = @schemas.at(keys)
        return unchecked(subject, path, t('schema_undeclared')) if schema.nil?

        judge(fixture, subject, path, schema.validate(fixture['body']).to_a)
      rescue StandardError => e
        unchecked(subject, path, t('validator_failed', error: e.message))
      end

      # Тела нет по двум разным причинам. «Операция без `requestBody`» и
      # «ответ 204» — утверждение самой спецификации, проверять там нечего и
      # проверкой это не считается. Тело, которое обещано и не описано, —
      # пробел спецификации: проверить нечем.
      def absent(fixture, subject, path)
        return nil if fixture['source'] == SPEC_EXAMPLE

        unchecked(subject, path, t('body_undeclared'))
      end

      def judge(fixture, subject, path, errors)
        return Finding.new(kind: :passed, subject: subject, json_path: path) if errors.empty?

        kind = fixture['source'] == SPEC_EXAMPLE ? :failed : :synthesized
        Finding.new(kind: kind, subject: subject, json_path: path, message: mismatch(errors))
      end

      def unchecked(subject, path, message)
        Finding.new(kind: :unchecked, subject: subject, json_path: path, message: message)
      end

      # Первое расхождение называется полем и ключевым словом схемы
      # (`enum`, `pattern`, `maxLength`), остальные — числом: список из
      # двадцати строк про одно тело отчёт не читает никто.
      def mismatch(errors)
        first = errors.first
        text = t('mismatch', field: field_of(first['data_pointer']), keyword: first['type'])
        return text if errors.size == 1

        "#{text} #{t('mismatch_more', count: errors.size - 1)}"
      end

      # Указатель JSON Pointer вида "/recipient/phone" читается как путь поля.
      def field_of(pointer)
        text = pointer.to_s.delete_prefix('/').tr('/', '.')
        text.empty? ? t('whole_body') : text
      end

      def subject(part, name)
        t("subject_#{part}", name: name)
      end

      def t(key, **params)
        Texts.t("validators.#{key}", **params)
      end
    end
  end
end
