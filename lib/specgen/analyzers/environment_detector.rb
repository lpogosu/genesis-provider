# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Отличает песочницу провайдера от его продакшен-хоста.
    #
    # Формально этого не сообщает ни одна спецификация:
    # `servers[].description` — свободная подпись, а имя хоста — просто имя,
    # поэтому единственное доступное обоснование — слово. Лексикон ниже —
    # словарь индустрии, а не какого-то одного провайдера, поэтому он живёт
    # в lib/, а не в rules/.
    #
    # Токены песочницы проверяются первыми намеренно: принять продакшен-хост
    # за песочницу стоит одного неудачного тестового вызова, обратная
    # ошибка — настоящего платежа.
    module EnvironmentDetector
      TOKENS = {
        sandbox: %w[sandbox test testing staging stage dev develop development demo uat preprod],
        production: %w[production prod live]
      }.freeze

      # Описание человек пишет затем, чтобы классифицировать сервер; имя
      # хоста содержит нужное слово лишь по совпадению.
      DESCRIPTION_CONFIDENCE = 0.8
      HOST_CONFIDENCE = 0.7

      SCHEME = %r{\A[a-z][a-z0-9+.-]*://}i
      WORD_BOUNDARY = /[^a-z0-9]+/

      # Сначала описание, потом хост.
      # @param url [String] URL сервера, как он написан в спецификации
      # @param description [String, nil] описание сервера, как оно написано
      # @return [IR::Derived, nil] nil, если ни одно слово не называет
      #   окружение и предупредить должен вызывающий
      def self.call(url:, description: nil)
        detect(description, 'description', DESCRIPTION_CONFIDENCE) ||
          detect(host_of(url), 'host', HOST_CONFIDENCE)
      end

      # @param text [String, nil] текст, из которого читаем слова
      # @param where [String] что это за текст, для строки обоснования
      # @param confidence [Float] сколько стоит это место
      # @return [IR::Derived, nil]
      def self.detect(text, where, confidence)
        found = token_hit(words_of(text))
        return nil if found.nil?

        environment, word = found
        evidence = Texts.t('analyzers.info.environment_evidence',
                           place: Texts.t("analyzers.info.environment_place.#{where}"),
                           text: text.inspect, word: word.inspect, environment: environment)
        IR::Derived.heuristic(environment, confidence: confidence, evidence: evidence)
      end

      # @param words [Array<String>]
      # @return [Array(Symbol, String), nil] окружение и слово, его доказавшее
      def self.token_hit(words)
        TOKENS.each do |environment, tokens|
          hit = tokens.find { |token| words.include?(token) }
          return [environment, hit] unless hit.nil?
        end
        nil
      end

      # Authority-часть URL. Порт, учётные данные и `{переменные}` не
      # требуют отдельного случая: они отсеиваются при разбиении на слова.
      # @param url [String, nil]
      # @return [String]
      def self.host_of(url)
        url.to_s.sub(SCHEME, '').split('/').first.to_s
      end

      # @param text [String, nil]
      # @return [Array<String>] ASCII-слова в нижнем регистре
      def self.words_of(text)
        text.to_s.downcase.split(WORD_BOUNDARY).reject(&:empty?)
      end
    end
  end
end
