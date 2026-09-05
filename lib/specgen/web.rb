# frozen_string_literal: true

require 'json'
require 'socket'
require 'stringio'
require 'tmpdir'

require 'rack'

require_relative '../specgen'
require_relative 'web/errors'
require_relative 'web/responses'
require_relative 'web/params'
require_relative 'web/catalog'
require_relative 'web/auth_text'
require_relative 'web/units_text'
require_relative 'web/summary'
require_relative 'web/pipeline'
require_relative 'web/api'
require_relative 'web/static'
require_relative 'web/app'
require_relative 'web/server'

module SpecGen
  # Тонкий HTTP-слой над конвейером: тот же разбор, та же генерация, тот же
  # отчёт, только результат уходит в JSON, а не в файлы.
  #
  # Границу видно по составу каталога: здесь есть маршруты, разбор тела
  # запроса, конверт ошибки и сборка ответа — и нет ни одного решения о
  # спецификации. Роли полей, единицы суммы, статусы и покрытие приходят
  # готовыми из lib/specgen/**, а строки для человека — от тех же
  # презентеров, которые печатает CLI. Фронт получает результат и ничего не
  # вычисляет; веб-слой ничего не вычисляет тоже.
  module Web
    # @param specs_dir [String] каталог со спецификациями для /api/specs
    # @param public_dir [String] каталог со собранным фронтом, если он есть
    # @return [App] Rack-приложение
    def self.app(specs_dir: Batch::DEFAULT_DIR, public_dir: File.join(SpecGen::ROOT, 'public'))
      App.new(specs_dir: specs_dir, public_dir: public_dir)
    end
  end
end
