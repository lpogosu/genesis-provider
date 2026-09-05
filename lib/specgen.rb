# frozen_string_literal: true

require_relative 'specgen/version'
require_relative 'specgen/errors'
require_relative 'specgen/texts'
require_relative 'specgen/spec_loader'
require_relative 'specgen/overlay'
require_relative 'specgen/ir'
require_relative 'specgen/rules'
require_relative 'specgen/matchers'
require_relative 'specgen/analyzers'
require_relative 'specgen/generators'
require_relative 'specgen/reporter'
require_relative 'specgen/batch'

# Генератор интеграций с платёжными провайдерами из OpenAPI-спецификаций.
#
# У конвейера одна стадия на каталог внутри lib/specgen/:
#
#   SpecLoader → OverlayApplier → Analyzers → IR → Generators → Validators → Reporter
#
# Ядро провайдер-нейтрально. Оно работает с ролями эндпоинтов и полей и
# читает свои справочники из rules/. Всё, что специфично для одного
# провайдера, живёт в rules/ (данные) или в файле OpenAPI Overlay, но никогда
# в lib/.
module SpecGen
  # Корень репозитория, вычисленный от этого файла, чтобы CLI работал из
  # любого рабочего каталога.
  ROOT = File.expand_path('..', __dir__).freeze
  # Справочники: роли полей, синонимы статусов, ISO 4217, профили подписи.
  RULES_DIR = File.join(ROOT, 'rules').freeze
  # ERB-шаблоны, по одному на генерируемый артефакт.
  TEMPLATES_DIR = File.join(ROOT, 'templates').freeze
  # Тексты для человека по языкам: locales/<код>/<стадия>.yml.
  LOCALES_DIR = File.join(ROOT, 'locales').freeze
end
