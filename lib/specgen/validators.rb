# frozen_string_literal: true

require 'json_schemer'

require_relative 'validators/finding'
require_relative 'validators/result'
require_relative 'validators/schemas'
require_relative 'validators/targets'
require_relative 'validators/fixture_check'
require_relative 'validators/expression'
require_relative 'validators/fixture_set'
require_relative 'validators/platform'
require_relative 'validators/fake_client'
require_relative 'validators/payment'
require_relative 'validators/sandbox'
require_relative 'validators/run/judge'
require_relative 'validators/run/base'
require_relative 'validators/run/prechecks'
require_relative 'validators/run/creation'
require_relative 'validators/run/polling'
require_relative 'validators/run/callbacks'
require_relative 'validators/run/extras'
require_relative 'validators/service_check'

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
  # Проверок две, и они отвечают на разные вопросы. Сверка (`check`) говорит,
  # правильной ли формы то, что собрано: тела из fixtures.json против схем
  # спецификации. Прогон (`exercise`) говорит, работает ли то, что собрано:
  # сгенерированный класс исполняется на тех же фикстурах с подменёнными
  # платформой и HTTP-клиентом. Первая проверяет данные, вторая — код; ни
  # одна не выходит в сеть.
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

    # Прогон сгенерированного класса на его же фикстурах: класс загружается в
    # изолированный модуль с подменой базового класса платформы, HTTP-клиент
    # отвечает телами из fixtures.json, сети нет.
    #
    # Спецификация здесь не нужна: всё, чем проверяется класс, уже записано в
    # артефактах и в модели провайдера. Нет одного из двух файлов — прогонять
    # нечего, и это пустой итог, а не отказ.
    #
    # @param profile [IR::ProviderProfile] модель провайдера
    # @param rules [Rules::Registry] справочники: контракт платформы
    # @param service_file [String, nil] путь к записанному service.rb
    # @param fixtures_file [String, nil] путь к записанному fixtures.json
    # @return [Result]
    def self.exercise(profile:, rules:, service_file:, fixtures_file:)
      return Result.new if service_file.nil? || fixtures_file.nil?

      ServiceCheck.new(profile: profile, rules: rules, service_file: service_file,
                       fixtures_file: fixtures_file).call
    end
  end
end
