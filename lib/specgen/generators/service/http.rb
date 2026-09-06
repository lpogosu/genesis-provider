# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Строки HTTP-обмена, общие для всех методов, которые ходят к
      # провайдеру: URL из пути операции с подстановкой параметров по их
      # ролям, вызов клиента по HTTP-методу, проверка успешного кода.
      #
      # Интерфейс клиента — допущение (эксперты: client.post(url, payload,
      # headers), client.get(url, headers)); ответ читается как
      # response.status и response.body.
      class Http
        # HTTP-методы, у которых есть тело запроса.
        WITH_BODY = %i[post put patch].freeze
        PATH_PARAM = /\{([^}]+)\}/
        # Отступ тела метода и ширина `url = ` — по ним выравнивается
        # продолжение длинной строки.
        INDENT = 6
        ASSIGN = 6
        DEFAULT_SUCCESS = [200].freeze

        # @param ctx [Context]
        def initialize(ctx)
          @ctx = ctx
        end

        # @param operation [IR::Operation]
        # @return [Array(Array<String>, Array<String>)] строки `url = "..."`
        #   и комментарии TODO о параметрах пути без роли
        def url(operation)
          todos = []
          path = operation.path.gsub(PATH_PARAM) do
            "\#{#{path_param(operation, Regexp.last_match(1), todos)}}"
          end
          path = "#{path}?\#{URI.encode_www_form(auth_query)}" if query_auth?
          [wrap("\#{BASE_URL}#{path}"), todos]
        end

        # Путь с несколькими подстановками в строку не влезает: у GOV.UK Pay
        # /v1/payments/{paymentId}/refunds/{refundId} даёт 117 знаков, и
        # Layout/LineLength видит это в сгенерированном коде. Режем по
        # границе сегмента пути и сцепляем соседние литералы обратным
        # слэшем, выравнивая продолжение по открывающей кавычке.
        #
        # @param inner [String] содержимое строкового литерала
        # @return [Array<String>] строки присваивания url
        def wrap(inner)
          head = "url = \"#{inner}\""
          return [head] if INDENT + head.length <= Ruby::WIDTH

          chunks = fold(segments(inner))
          last = chunks.size - 1
          chunks.each_with_index.map do |chunk, index|
            prefix = index.zero? ? 'url = ' : ' ' * ASSIGN
            suffix = index == last ? '' : ' \\'
            "#{prefix}\"#{chunk}\"#{suffix}"
          end
        end

        # Границы разреза: конец каждого сегмента пути, но никогда внутри
        # подстановки — иначе получится не строка, а синтаксическая ошибка.
        # @return [Array<String>]
        def segments(inner)
          inner.scan(/\#\{[^}]*\}|[^#]+|#/).flat_map do |part|
            part.start_with?('#{') ? [part] : part.split(%r{(?<=/)})
          end.reject(&:empty?)
        end

        # @return [Array<String>] сегменты, собранные в строки по ширине
        def fold(parts)
          room = Ruby::WIDTH - INDENT - ASSIGN - 4
          parts.each_with_object([]) do |part, lines|
            if lines.empty? || lines.last.length + part.length > room
              lines << part
            else
              lines[-1] += part
            end
          end
        end

        # @param operation [IR::Operation]
        # @param payload [String, nil] выражение тела для методов с телом
        # @return [String] `response = client.post(url, payload, headers)`
        def request(operation, payload: nil, headers: nil)
          headers ||= @ctx.helper(:auth_headers)
          verb = operation.http_method
          args = WITH_BODY.include?(verb) ? ['url', payload || '{}', headers] : ['url', headers]
          "response = #{@ctx.helper(:client)}.#{verb}(#{args.join(', ')})"
        end

        # @param operation [IR::Operation]
        # @return [String] "response.status == 201" или "[200, 202].include?(...)"
        def success_check(operation)
          codes = success_codes(operation)
          return "response.status == #{codes.first}" if codes.one?

          "#{Ruby.array(codes)}.include?(response.status)"
        end

        # @param operation [IR::Operation]
        # @return [Array<Integer>] объявленные коды 2xx, иначе [200]
        def success_codes(operation)
          codes = operation.success_responses.filter_map(&:code).uniq.sort
          codes.empty? ? DEFAULT_SUCCESS : codes
        end

        # @return [Boolean] учётные данные уходят в строку запроса
        def query_auth?
          @ctx.auth_scheme&.dig(:location) == :query
        end

        private

        # Выражение для параметра пути: по роли параметра, иначе лучший
        # кандидат — идентификатор операции у провайдера — с TODO.
        def path_param(operation, name, todos)
          parameter = operation.parameters_in(:path).find { |param| param.name == name }
          role = parameter&.role
          expression = role&.known? ? @ctx.accessor(role.value) : nil
          return expression if expression

          guess = @ctx.accessor(:provider_operation_id) || 'nil'
          todos.concat(Ruby.comment(@ctx.t('path_param_unknown', name: name, guess: guess),
                                    width: Ruby::WIDTH - 6, prefix: '# TODO: '))
          guess
        end

        def auth_query
          'auth_query'
        end
      end
    end
  end
end
