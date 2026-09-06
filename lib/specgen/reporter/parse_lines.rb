# frozen_string_literal: true

module SpecGen
  module Reporter
    # Что генератор понял в спецификации — три строки перед генерацией.
    #
    # Зачем это есть. Описание кейса показывает ожидаемый вывод команды
    # именно так: сначала «Parsing spec... Found 5 endpoints», авторизация и
    # подпись вебхука, и только потом строки о записанных файлах. Без этого
    # человек видит четыре строки «ok» и не знает, что инструмент вообще
    # разобрал: понял ли он пять операций или одну, нашёл ли авторизацию.
    #
    # Наследуемся от Summary намеренно. Фразы про заголовок разбора и про
    # авторизацию у экрана `analyze` уже есть, и второй способ сказать то же
    # самое рано или поздно разошёлся бы с первым. Здесь берутся ровно те же
    # методы, а добавляется только список эндпоинтов и строка подписи —
    # ничего из этого заново не вычисляется, всё читается из профиля.
    class ParseLines < Summary
      # Сколько эндпоинтов перечислять; остальные — числом. Спецификации
      # Adyen и Mollie дают десятки операций, и вывалить их все в консоль
      # значит спрятать за ними строки о записанных файлах.
      MAX_ENDPOINTS = 8

      # @return [String] преамбула, переводы строк LF
      def render
        "#{lines.compact.join("\n")}\n"
      end

      private

      def lines
        [header, endpoints, auth_summary, signature_summary]
      end

      # @return [String, nil] строка со списком «METHOD /path»
      def endpoints
        return nil if profile.operations.empty?

        "#{INDENT}#{(shown_endpoints + rest_of_endpoints).join(', ')}"
      end

      def shown_endpoints
        profile.operations.first(MAX_ENDPOINTS).map do |operation|
          "#{operation.http_method.to_s.upcase} #{operation.path}"
        end
      end

      def rest_of_endpoints
        hidden = profile.operations.size - MAX_ENDPOINTS
        hidden.positive? ? [Texts.t('cli.parse.endpoints_more', count: hidden)] : []
      end

      # Summary#auth отдаёт массив строк вместе с обоснованием; преамбуле
      # нужна одна строка, поэтому берётся первая.
      # @return [String, nil]
      def auth_summary
        Array(auth).flatten.compact.first
      end

      # @return [String, nil] подпись вебхука одной строкой
      def signature_summary
        webhook = profile.webhooks.first
        return nil if webhook.nil?

        signature = webhook.signature
        return Texts.t('cli.parse.webhook_unsigned', path: webhook.path) if signature.nil?

        Texts.t('cli.parse.webhook_signed', path: webhook.path,
                                            header: signature.header.value,
                                            algorithm: signature.algorithm.value)
      end
    end
  end
end
