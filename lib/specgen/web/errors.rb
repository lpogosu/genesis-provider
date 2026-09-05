# frozen_string_literal: true

module SpecGen
  module Web
    # Ошибка запроса к API: тело не разобралось, оно слишком велико, нет
    # такого маршрута, не названа спецификация.
    #
    # Наследуется от SpecGen::Error, поэтому один обработчик в App ловит и
    # ошибки конвейера (битая спецификация), и ошибки протокола: наружу и
    # те и другие уходят одним конвертом с местом ошибки, без стектрейса.
    #
    # Формулировки. Ошибки конвейера приходят с текстом из locales/, а у
    # ошибок протокола своего ключа локали пока нет. Пока его нет, в
    # `message` уходит машинный код (`route_not_found`), а фраза для
    # человека остаётся за фронтом; как только в локали появится ключ
    # `web.errors.<код>`, он подхватится сам, без правки кода.
    class RequestError < SpecGen::Error
      # Код ошибки → код HTTP. Всё, чего здесь нет, — 422: спецификацию
      # приняли, но работать с ней не смогли.
      STATUSES = {
        invalid_json: 400,
        route_not_found: 404,
        body_too_large: 413
      }.freeze
      DEFAULT_STATUS = 422
      # Ключи локали, которые уже существуют и подходят по смыслу: незачем
      # заводить второй текст про ненайденную спецификацию.
      TEXT_KEYS = { spec_unknown: 'cli.spec_not_found' }.freeze
      KEY_PREFIX = 'web.errors'

      # @return [Symbol] машинный код ошибки, он же ключ STATUSES
      attr_reader :code

      # @param code [Symbol] машинный код ошибки
      # @param file [String, nil] файл, к которому относится ошибка
      # @param path [String, nil] место внутри файла
      def initialize(code, file: nil, path: nil)
        @code = code
        super(self.class.message_for(code), file: file, path: path)
      end

      # @return [Integer] код HTTP для этой ошибки
      def status
        STATUSES.fetch(code, DEFAULT_STATUS)
      end

      # @param code [Symbol]
      # @return [String] текст локали, если он есть, иначе машинный код
      def self.message_for(code)
        key = ["#{KEY_PREFIX}.#{code}", TEXT_KEYS[code]].compact.find { |name| Texts.key?(name) }
        key.nil? ? code.to_s : Texts.t(key)
      end
    end
  end
end
