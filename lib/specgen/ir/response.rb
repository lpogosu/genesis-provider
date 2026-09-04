# frozen_string_literal: true

module SpecGen
  module IR
    # Один объявленный ответ операции.
    #
    #   status       "201", "4XX" или "default", дословно
    #   description  дословно
    #   schema       имя схемы тела в profile.schemas или nil
    #   headers      имена объявленных заголовков ответа, например
    #                ["Retry-After"]
    #   examples     {имя => значение}; одиночный `example` кладётся под
    #                ключ "default"
    #   json_path    "$.paths['/x'].post.responses['201']"
    Response = Struct.new(:status, :description, :schema, :headers, :examples, :json_path,
                          keyword_init: true)

    # Проверки и предикаты Response.
    class Response
      include Node

      STATUS = /\A(?:[1-5]\d{2}|[1-5]XX|default)\z/
      # Ключ, под которым в `examples` лежит одиночный `example`.
      DEFAULT_EXAMPLE = 'default'

      # @param status [String]
      # @param description [String, nil]
      # @param schema [String, nil]
      # @param headers [Array<String>]
      # @param examples [Hash{String => Object}]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(status:, description: nil, schema: nil, headers: [], examples: {},
                     json_path: nil)
        unless status.is_a?(String) && status.match?(STATUS)
          raise ArgumentError,
                'код ответа: ожидается "NNN", "NXX" или "default", ' \
                "получено #{status.inspect}"
        end

        super
      end

      # @return [Integer, nil] числовой код; nil для диапазонов и default
      def code
        Integer(status, exception: false)
      end

      # @return [Boolean] 2xx
      def success?
        status.start_with?('2')
      end

      # @return [Boolean] объявлен ли заголовок с таким именем
      def header?(name)
        headers.any? { |header| header.casecmp?(name) }
      end
    end
  end
end
