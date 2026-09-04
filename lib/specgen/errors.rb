# frozen_string_literal: true

module SpecGen
  # Корень иерархии ошибок. Каждая ошибка, которую генератор поднимает на
  # пользовательском вводе, несёт файл спецификации и JSONPath виноватого
  # элемента, когда они известны: благодаря этому CLI печатает
  # «файл, $.путь: сообщение», а не стектрейс. Ничто в lib/ не поднимает
  # голую строку.
  class Error < StandardError
    # @return [String, nil] файл спецификации, к которому относится ошибка
    attr_reader :file
    # @return [String, nil] место внутри файла: JSONPath вида "$.paths" либо
    #   позиция «строка 5, столбец 3» для ошибок синтаксиса
    attr_reader :path
    # @return [String, nil] сообщение без префикса с местом ошибки
    attr_reader :detail

    # @param message [String, nil] описание для человека
    # @param file [String, nil] файл спецификации, к которому относится ошибка
    # @param path [String, nil] JSONPath (или позиция) внутри этого файла
    def initialize(message = nil, file: nil, path: nil)
      @file = file
      @path = path
      @detail = message
      super(message)
    end

    # @return [String] сообщение с префиксом места, когда место известно
    def to_s
      base = super
      return base if location.empty?

      "#{location}: #{base}"
    end

    # @return [String] «файл, $.путь»; любая из половин может отсутствовать
    def location
      return path.to_s if file.nil?
      return file if path.nil?

      Texts.t('errors.location', file: file, path: path)
    end
  end

  # Стадия загрузки: файла нет или он не читается, битый YAML или JSON,
  # документ вообще не OpenAPI, версия OpenAPI не поддерживается.
  class SpecLoadError < Error; end

  # Стадия разбора: документ — OpenAPI, но структурно непригоден: нет
  # секции `paths`, `$ref` не разрешается или замкнут в цикл, неизвестный
  # тип схемы.
  class SpecParseError < Error; end

  # Стадия справочников: что-то не так с данными в rules/ — файла нет или он
  # битый, роль вне IR::Roles, синоним заявлен двумя ролями, экспонента
  # валюты вне допустимого диапазона, роль контракта, которую не обслуживает
  # ни один метод. В отличие от остальных ошибок эта никогда не вина
  # пользователя: справочники наши, поэтому сообщение перечисляет сразу все
  # найденные проблемы, а прогон останавливается до того, как неверный
  # синоним доберётся до сгенерированного кода.
  class RulesError < Error; end

  # Стадия генерации: шаблон не отрендерился, артефакт не удалось записать,
  # сгенерированный код не прошёл собственную проверку синтаксиса.
  class GenerationError < Error; end

  # Слой текстов (locales/): нет каталога языка, нет ключа, ключ задан
  # дважды, не хватает параметра подстановки. Как и RulesError, это всегда
  # наша ошибка, а не пользователя: тест на полноту локалей ловит её до
  # запуска, а сюда она попадает только если тест не запускали.
  class LocaleError < Error; end
end
