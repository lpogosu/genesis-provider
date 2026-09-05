# frozen_string_literal: true

require 'json_schemer'

require_relative 'validators/finding'
require_relative 'validators/result'
require_relative 'validators/schemas'
require_relative 'validators/targets'
require_relative 'validators/fixture_check'

module SpecGen
  # Стадия проверки: то, что генератор собрал, сверяется с той самой
  # спецификацией, из которой оно выведено.
  #
  # Зачем. Эксперты кейса сказали, что живой трафик к провайдеру не нужен и
  # оценивается сгенерированный класс. Тогда доказать, что запрос правильный,
  # можно единственным способом — проверить его против схемы запроса из
  # спецификации. Круг замыкается: спецификация → анализ → генерация →
  # обратно к спецификации; если тело не проходит схему, где-то мы соврали.
  #
  # Что проверяется. Тела из записанного fixtures.json: каждый запрос против
  # схемы тела своей операции, каждый ответ против схемы своего кода, каждое
  # уведомление против схемы тела вебхука. Фикстуры — это и есть то, что
  # собрал генератор: заголовки, ключ идемпотентности и подпись в них
  # считают те же презентеры, что печатают сервис.
  #
  # Чем проверяется. `json_schemer` — валидатор JSON Schema с поддержкой
  # диалектов OpenAPI 3.0 и 3.1, лицензия MIT. Готовые обёртки над OpenAPI
  # не подошли по проверяемым причинам, и они записаны в DEPENDENCIES.md:
  # `committee` отказывается читать OpenAPI 3.1 (`OpenAPI3Unsupported`), а
  # `openapi_first` падает на Windows на пути с буквой диска
  # (`URI::InvalidComponentError`). Обе построены на том же json_schemer, так
  # что взят движок без обёртки.
  #
  # Чего стадия не делает. Она не блокирует генерацию: артефакты уже
  # записаны, проверка сообщает, а не отменяет. Исключение валидатора
  # наружу не выходит — любая его неудача становится находкой вида
  # `unchecked` с местом в спецификации.
  module Validators
    # Спецификации может не быть: профиль иногда собирают в обход загрузчика
    # — так делают примеры в тестах и так может сделать чужой код, который
    # берёт наш IR готовым. Сверять тогда не с чем, и это не ошибка: пустой
    # итог означает «проверок не было», а не «все прошли».
    #
    # @param document [SpecLoader::Document, nil] спецификация, из которой всё
    #   выведено (после overlay, с разрешёнными `$ref`)
    # @param profile [IR::ProviderProfile] модель провайдера
    # @param fixtures_file [String, nil] путь к записанному fixtures.json
    # @return [Result]
    # @raise [ValidationError] артефакт фикстур не читается как JSON
    def self.check(document:, profile:, fixtures_file:)
      return Result.new if document.nil? || fixtures_file.nil?

      FixtureCheck.new(document: document, profile: profile,
                       fixtures_file: fixtures_file).call
    end
  end
end
