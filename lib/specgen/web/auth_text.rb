# frozen_string_literal: true

module SpecGen
  module Web
    # Строка об авторизации для API — ровно та, которую печатает
    # `./integrate analyze`.
    #
    # Наследование здесь не приём, а требование: строку собирает
    # Reporter::Summary, и второй способ её собрать означал бы, что экран и
    # ответ API однажды разойдутся. Наследник открывает одну готовую строку,
    # ничего не считая сам.
    class AuthText < Reporter::Summary
      # @return [String] «схема Bearer, тип bearer, заголовок …»
      def text
        auth.first
      end
    end
  end
end
