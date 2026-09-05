# frozen_string_literal: true

module SpecGen
  module Web
    # Сборка HTTP-ответов: JSON, конверт ошибки, файл из public/ и ответ на
    # предварительный запрос CORS.
    #
    # Заголовки строчными буквами — этого требует Rack 3. Кириллица уходит
    # как есть: JSON.generate не экранирует не-ASCII, а charset объявлен в
    # content-type, поэтому фронт получает текст, а не \u-последовательности.
    module Responses
      JSON_TYPE = 'application/json; charset=utf-8'
      # Фронт собирается отдельно (Lovable) и живёт на другом порту, поэтому
      # без CORS до API не достучаться ни один браузер.
      CORS = {
        'access-control-allow-origin' => '*',
        'access-control-allow-methods' => 'GET, POST, OPTIONS',
        'access-control-allow-headers' => 'content-type',
        'access-control-max-age' => '86400'
      }.freeze

      # @param status [Integer]
      # @param data [Hash] структура ответа
      # @return [Array(Integer, Hash, Array<String>)] ответ Rack
      def self.json(status, data)
        body = "#{JSON.generate(data)}\n"
        [status, headers(JSON_TYPE, body), [body]]
      end

      # Единый конверт ошибки: наружу уходят только сообщение и место, но
      # никогда не стектрейс.
      # @param status [Integer]
      # @param message [String]
      # @param code [Symbol, nil] машинный код для фронта
      # @param file [String, nil] файл спецификации
      # @param location [String, nil] JSONPath или позиция внутри файла
      # @return [Array] ответ Rack
      def self.error(status, message:, code: nil, file: nil, location: nil)
        json(status, { error: { code: code, message: message, file: file,
                                location: location } })
      end

      # @param content [String] уже прочитанное тело файла
      # @param type [String] значение content-type
      # @return [Array] ответ Rack
      def self.file(content, type)
        [200, headers(type, content), [content]]
      end

      # Ответ на OPTIONS: тела нет, важны только заголовки. content-length у
      # 204 нет намеренно — Rack 3 (и RFC 9110) его там запрещают.
      # @return [Array] ответ Rack
      def self.preflight
        [204, CORS.dup, []]
      end

      # @param type [String]
      # @param body [String]
      # @return [Hash{String => String}]
      def self.headers(type, body)
        CORS.merge('content-type' => type, 'content-length' => body.bytesize.to_s)
      end
    end
  end
end
