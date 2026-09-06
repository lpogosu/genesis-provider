# frozen_string_literal: true

module SpecGen
  module Validators
    # Записанный fixtures.json как источник данных прогона: учётные данные,
    # адрес, запросы, ответы и уведомления.
    #
    # Читается файл на диске, а не то, что генератор держал в памяти: прогон
    # обязан доказывать, что работают именно записанные артефакты. Ключи
    # фикстур — строки, поэтому всё, что отсюда выходит, тоже строки; в
    # символы их переводит только тот, кто сравнивает с кодом платформы.
    class FixtureSet
      # @return [Hash] разобранный документ фикстур
      attr_reader :data

      # @param file [String] путь к записанному fixtures.json
      # @raise [ValidationError] файл не читается как JSON
      def initialize(file)
        @file = file
        @data = read(file)
      end

      # @return [String, nil] базовый адрес, с которым собраны фикстуры
      def base_url
        @data['base_url']
      end

      # Учётные данные-заглушки. Сервис читает их и строкой, и символом
      # (`provider.credentials[:api_key]` в заголовках, но
      # `credentials[SIGNATURE_SECRET_KEY]` — символом из константы), поэтому
      # хеш отдаётся сразу в обоих видах.
      # @return [Hash]
      def credentials
        table = @data['credentials']
        return {} unless table.is_a?(Hash)

        table.each_with_object({}) do |(key, value), all|
          all[key] = value
          all[key.to_sym] = value
        end
      end

      # @param key [String] ключ операции
      # @return [Hash, nil] фикстура запроса этой операции
      def request(key)
        list('requests').find { |item| item['name'] == key }
      end

      # @param key [String] ключ операции
      # @return [Array<Hash>] фикстуры ответов этой операции по порядку
      def responses(key)
        list('responses').select { |item| item['operation'] == key }
      end

      # @param key [String] ключ операции
      # @param codes [Array<Integer>] коды успеха операции
      # @return [Hash, nil] первый успешный ответ
      def success_response(key, codes)
        responses(key).find { |item| codes.include?(item['status'].to_i) }
      end

      # @return [Array<Hash>] фикстуры уведомлений по порядку
      def notifications
        list('notifications')
      end

      # @param name [String] ключ верхнего уровня
      # @return [Array<Hash>]
      def list(name)
        value = @data[name]
        value.is_a?(Array) ? value : []
      end

      private

      def read(file)
        ::JSON.parse(File.read(file, encoding: 'UTF-8'))
      rescue ::JSON::ParserError, SystemCallError => e
        message = Texts.t('validators.fixtures_unreadable', error: e.message)
        raise ValidationError.new(message, file: file)
      end
    end
  end
end
