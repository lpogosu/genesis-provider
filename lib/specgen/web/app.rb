# frozen_string_literal: true

module SpecGen
  module Web
    # Rack-приложение: пять маршрутов API, статика фронта и один конверт
    # ошибки на все случаи.
    #
    # Веб-слой не имеет права уронить процесс и не имеет права показать
    # стектрейс. Ошибка конвейера — 422 с файлом и местом, ошибка протокола
    # — свой код, всё неожиданное — 500 с тем же конвертом, а подробности
    # уходят в лог сервера, а не клиенту.
    #
    # Здесь нет ни разбора спецификаций, ни генерации: App разбирает запрос
    # и печатает ответ. Это граница «фронт — оболочка, а не реализация»,
    # проведённая на сервере: всё, что вычисляется, вычисляется в Ruby и до
    # этого класса.
    class App
      ROUTES = {
        ['GET', '/api/health'] => :health,
        ['GET', '/api/specs'] => :specs,
        ['GET', '/api/batch'] => :batch,
        ['POST', '/api/generate'] => :generate,
        ['POST', '/api/analyze'] => :analyze
      }.freeze
      # Действия, которым нужно тело запроса.
      WITH_PARAMS = %i[generate analyze].freeze
      API_PREFIX = '/api/'
      SPEC_ERROR_STATUS = 422
      INTERNAL_ERROR_STATUS = 500
      # Ошибка конвейера → машинный код для фронта. Класс ошибки уже
      # называет стадию, на которой всё сломалось; незачем разбирать текст.
      ERROR_CODES = {
        SpecLoadError => :spec_load, SpecParseError => :spec_parse, OverlayError => :overlay,
        RulesError => :rules, GenerationError => :generation, LocaleError => :locale
      }.freeze
      DEFAULT_ERROR_CODE = :spec_invalid

      # @param specs_dir [String] каталог со спецификациями
      # @param public_dir [String] каталог со собранным фронтом
      def initialize(specs_dir: Batch::DEFAULT_DIR,
                     public_dir: File.join(SpecGen::ROOT, 'public'))
        @api = Api.new(specs_dir: specs_dir)
        @static = Static.new(public_dir)
      end

      # @param env [Hash] окружение Rack
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)
        return Responses.preflight if request.options?

        dispatch(request)
      rescue RequestError => e
        Responses.error(e.status, message: message(e), code: e.code, file: e.file,
                                  location: e.path)
      rescue SpecGen::Error => e
        Responses.error(SPEC_ERROR_STATUS, message: message(e), code: code_of(e), file: e.file,
                                           location: e.path)
      rescue StandardError => e
        internal_error(env, e)
      ensure
        Texts.locale = nil
      end

      private

      def dispatch(request)
        action = ROUTES[[request.request_method, request.path_info]]
        return respond(action, request) unless action.nil?
        raise RequestError.new(:route_not_found, file: request.path_info) if api?(request)

        @static.call(request) || raise(RequestError.new(:route_not_found,
                                                        file: request.path_info))
      end

      def respond(action, request)
        return Responses.json(200, @api.public_send(action)) unless WITH_PARAMS.include?(action)

        params = Params.parse(request)
        # Язык выбирается на запрос и сбрасывается в ensure: два клиента с
        # разными --locale не должны видеть язык друг друга.
        Texts.locale = params.locale
        Responses.json(200, @api.public_send(action, params))
      end

      def api?(request)
        request.path_info.start_with?(API_PREFIX)
      end

      def message(error)
        error.detail || error.message
      end

      def code_of(error)
        ERROR_CODES.fetch(error.class, DEFAULT_ERROR_CODE)
      end

      # Стектрейс — в лог сервера, клиенту только код: неожиданная ошибка не
      # должна рассказывать наружу об устройстве машины.
      def internal_error(env, error)
        log = env['rack.errors']
        log&.write("#{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}\n")
        Responses.error(INTERNAL_ERROR_STATUS, code: :internal_error,
                                               message: RequestError.message_for(:internal_error))
      end
    end
  end
end
