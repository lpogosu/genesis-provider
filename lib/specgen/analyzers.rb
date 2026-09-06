# frozen_string_literal: true

module SpecGen
  # Третья стадия конвейера. Каждый анализатор читает загруженный Document
  # и заполняет свою часть IR::ProviderProfile: провайдера, авторизацию,
  # операции, поля, суммы, статусы, вебхуки.
  #
  # Анализаторы независимы по контракту (docs/IR.md): ни один не читает то,
  # что записал другой, поэтому порядок запуска не может повлиять на
  # результат. Всё, что анализатор вывести не смог, становится
  # `Derived.unknown` плюс `profile.warn`, а не правдоподобной догадкой:
  # молчаливая ошибка в платёжной интеграции дороже одного ручного шага.
  module Analyzers
  end
end

require_relative 'analyzers/operations'
require_relative 'analyzers/base'
require_relative 'analyzers/environment_detector'
require_relative 'analyzers/security_requirements'
require_relative 'analyzers/schema_naming'
require_relative 'analyzers/note'
require_relative 'analyzers/constraint_reader'
require_relative 'analyzers/role_subjects'
require_relative 'analyzers/schema_flattener'
require_relative 'analyzers/negated_branch'
require_relative 'analyzers/condition_reader'
require_relative 'analyzers/schema_reader'
require_relative 'analyzers/content_reader'
require_relative 'analyzers/parameter_reader'
require_relative 'analyzers/role_evidence'
require_relative 'analyzers/response_shape'
require_relative 'analyzers/operation_role'
require_relative 'analyzers/operation_links'
require_relative 'analyzers/resource_affinity'
require_relative 'analyzers/operation_pairing'
require_relative 'analyzers/pairing_notes'
require_relative 'analyzers/role_veto'
require_relative 'analyzers/operation_notes'
require_relative 'analyzers/auth_scheme'
require_relative 'analyzers/schema_index'
require_relative 'analyzers/role_lookup'
require_relative 'analyzers/example_reader'
require_relative 'analyzers/status_reader'
require_relative 'analyzers/dedup_reader'
require_relative 'analyzers/error_code_reader'
require_relative 'analyzers/http_error_rules'
require_relative 'analyzers/webhook_events'
require_relative 'analyzers/signature_reader'
require_relative 'analyzers/currency_reader'
require_relative 'analyzers/unit_reader'
require_relative 'analyzers/info_analyzer'
require_relative 'analyzers/auth_analyzer'
require_relative 'analyzers/operation_analyzer'
require_relative 'analyzers/schema_analyzer'
require_relative 'analyzers/units_analyzer'
require_relative 'analyzers/status_analyzer'
require_relative 'analyzers/error_analyzer'
require_relative 'analyzers/webhook_analyzer'
require_relative 'analyzers/idempotency_analyzer'
require_relative 'analyzers/conditions_analyzer'
require_relative 'analyzers/runner'
