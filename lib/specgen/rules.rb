# frozen_string_literal: true

require_relative 'rules/normalizer'
require_relative 'rules/problems'
require_relative 'rules/duplicate_keys'
require_relative 'rules/document'
require_relative 'rules/checks'
require_relative 'rules/book'
require_relative 'rules/role_hints'
require_relative 'rules/roles_matchers'
require_relative 'rules/roles_book'
require_relative 'rules/statuses_book'
require_relative 'rules/currencies_book'
require_relative 'rules/signatures_book'
require_relative 'rules/idempotency_book'
require_relative 'rules/operations_book'
require_relative 'rules/conditions_book'
require_relative 'rules/auth_book'
require_relative 'rules/method_spec'
require_relative 'rules/contract_book'
require_relative 'rules/errors_book'
require_relative 'rules/registry'

module SpecGen
  # Справочники из rules/: синонимы имён полей для ролей IR::Roles, синонимы
  # статусов, экспоненты ISO 4217, профили подписи вебхуков, алиасы
  # заголовка идемпотентности, схемы авторизации, слова и веса, по которым
  # распознаётся роль операции, шаблоны, замечающие условную обязательность,
  # высказанную прозой, сам контракт Provider::BaseService и политика
  # действий по ошибкам провайдера.
  #
  # Поддержка нового провайдера задумана как новые строки в этих файлах и
  # никогда как новая ветка в lib/, а это держится только на том, что данным
  # можно доверять. Поэтому загрузчик строг: неизвестная роль, синоним,
  # занятый двумя ролями, экспонента валюты вне ISO 4217, роль контракта,
  # которую не обслуживает ни один метод, ключ, написанный в одном файле
  # дважды, — каждое останавливает прогон на старте, и все проблемы всех
  # справочников перечисляются сразу.
  module Rules
    # @param dir [String] каталог со справочниками
    # @return [Registry] все десять справочников, проверенные
    # @raise [RulesError] со списком всех найденных проблем
    def self.load(dir = SpecGen::RULES_DIR)
      Registry.load(dir)
    end
  end
end
