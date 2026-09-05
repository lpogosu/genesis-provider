# frozen_string_literal: true

module SpecGen
  module Web
    # Разобранное тело запроса к /api/generate и /api/analyze.
    #
    # Вход бывает двух видов: имя спецификации из каталога (`spec_id`) —
    # демонстрация в один клик, — либо загруженный текст (`content`). Всё,
    # что приходит от клиента, здесь же и проверяется: имя из каталога не
    # имеет права оказаться путём (`../../etc/passwd`), а тело больше лимита
    # не должно доходить до разбора — без лимита сервер кладётся одним
    # запросом.
    class Params
      # 5 МБ: самая большая настоящая спецификация в проекте — 218 КБ, так
      # что лимит щедрый, но конечный.
      MAX_BODY_BYTES = 5 * 1024 * 1024
      # Идентификатор из каталога: имя файла без расширения и без пути.
      SAFE_ID = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
      SAFE_NAME = /[^a-zA-Z0-9._-]+/
      DEFAULT_FILENAME = 'spec.yaml'

      # @return [String, nil] имя спецификации из каталога
      attr_reader :spec_id
      # @return [String, nil] текст загруженной спецификации
      attr_reader :content
      # @return [String] имя файла, под которым будет сохранён текст
      attr_reader :filename
      # @return [String, nil] имя провайдера, если клиент его назвал
      attr_reader :provider
      # @return [String, nil] текст файла OpenAPI Overlay 1.0.0
      attr_reader :overlay
      # @return [String, nil] код языка сообщений
      attr_reader :locale

      # @param request [Rack::Request]
      # @return [Params]
      # @raise [RequestError] тело больше лимита или не разбирается как JSON
      def self.parse(request)
        new(body(request))
      end

      # @param data [Hash] разобранное тело
      # @raise [RequestError] не названы ни spec_id, ни content
      def initialize(data)
        @spec_id = string(data['spec_id'])
        @content = string(data['content'])
        @provider = string(data['provider'])
        @overlay = string(data['overlay'])
        @locale = string(data['locale'])
        @filename = safe_filename(string(data['filename']))
        validate!
      end

      # @return [Boolean] спецификация пришла текстом, а не из каталога
      def upload?
        !content.nil?
      end

      # @param request [Rack::Request]
      # @return [Hash]
      def self.body(request)
        raw = read(request)
        return {} if raw.empty?

        data = JSON.parse(raw)
        raise RequestError, :invalid_json unless data.is_a?(Hash)

        data
      rescue JSON::ParserError
        raise RequestError, :invalid_json
      end

      # Читаем на байт больше лимита: этого достаточно, чтобы отличить
      # «ровно лимит» от «больше лимита», и не нужно доверять заголовку.
      # @param request [Rack::Request]
      # @return [String]
      def self.read(request)
        raise RequestError, :body_too_large if request.content_length.to_i > MAX_BODY_BYTES

        raw = request.body&.read(MAX_BODY_BYTES + 1).to_s
        raise RequestError, :body_too_large if raw.bytesize > MAX_BODY_BYTES

        raw
      end

      private

      def validate!
        raise RequestError, :spec_required if spec_id.nil? && content.nil?
        raise RequestError.new(:spec_unknown, file: spec_id) if bad_id?

        nil
      end

      def bad_id?
        !spec_id.nil? && !spec_id.match?(SAFE_ID)
      end

      def safe_filename(value)
        name = File.basename(value.to_s).gsub(SAFE_NAME, '_').delete_prefix('.')
        return DEFAULT_FILENAME unless Batch::EXTENSIONS.include?(File.extname(name).downcase)

        name
      end

      def string(value)
        return nil unless value.is_a?(String)

        text = value.strip
        text.empty? ? nil : value
      end
    end
  end
end
