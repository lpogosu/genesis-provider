# frozen_string_literal: true

module SpecGen
  # Провайдер-нейтральное промежуточное представление платёжного провайдера.
  #
  # Анализаторы читают загруженную спецификацию и заполняют свою часть
  # ProviderProfile; генераторы читают профиль и в спецификацию не заглядывают
  # никогда. Каждое выведенное значение обёрнуто в Derived, который несёт свой
  # источник и уверенность, поэтому report.md может объяснить каждое решение.
  # Словарь значений (роли полей, роли операций, внутренние статусы, действия
  # по ошибке) закрыт и живёт в IR::Roles; значение вне него — ошибка
  # программиста, а не пользовательский ввод, и поднимает ArgumentError уже
  # при создании объекта.
  #
  # Через все типы проходят два соглашения:
  #
  # * `nil` означает «в спецификации нет / не применимо»; `Derived.unknown` —
  #   «анализатор смотрел и вывести не смог». Предупреждать в отчёте надо
  #   только о втором.
  # * `to_h` возвращает поля в порядке объявления, разворачивая вложенные
  #   объекты, поэтому сериализованный профиль байт-в-байт устойчив.
  module IR
  end
end

require_relative 'ir/node'
require_relative 'ir/roles'
require_relative 'ir/derived'
require_relative 'ir/warning'
require_relative 'ir/info'
require_relative 'ir/server'
require_relative 'ir/auth'
require_relative 'ir/required_when'
require_relative 'ir/field'
require_relative 'ir/schema'
require_relative 'ir/parameter'
require_relative 'ir/response'
require_relative 'ir/operation'
require_relative 'ir/status_mapping'
require_relative 'ir/error_rule'
require_relative 'ir/signature_profile'
require_relative 'ir/webhook_event'
require_relative 'ir/webhook'
require_relative 'ir/units'
require_relative 'ir/idempotency'
require_relative 'ir/condition'
require_relative 'ir/provider_profile'
