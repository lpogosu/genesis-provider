# frozen_string_literal: true

require_relative 'diff/change'
require_relative 'diff/area'
require_relative 'diff/operations'
require_relative 'diff/authorization'
require_relative 'diff/amounts'
require_relative 'diff/statuses'
require_relative 'diff/error_map'
require_relative 'diff/webhooks'
require_relative 'diff/idempotence'
require_relative 'diff/request_fields'
require_relative 'diff/fields'
require_relative 'diff/conditions'
require_relative 'diff/versions'

module SpecGen
  # Сравнение двух версий спецификации одного провайдера — через IR, а не по
  # тексту файлов.
  #
  # Зачем стадия нужна. Спецификация провайдера живёт своей жизнью, а
  # интеграция уже написана. Текстовый diff двух YAML честно покажет
  # переставленные ключи и переписанные описания и ничего не скажет о том,
  # надо ли перегенерировать сервис. Сравнение идёт по тому же
  # промежуточному представлению, из которого собран сервис, поэтому у
  # каждого отличия есть ответ на единственный важный вопрос: меняет ли оно
  # сгенерированный код (`:code`), только документацию и фикстуры (`:docs`)
  # или ничего, кроме отчёта (`:info`).
  #
  # Что сравнивается, перечислено разделами (COMPARATORS): операции,
  # авторизация, единицы суммы, статусы, коды ошибок, вебхуки,
  # идемпотентность, поля запросов операций контракта и условия
  # взаимодействия. Описания и примеры не сравниваются намеренно: они
  # меняются в каждой второй версии, и отчёт утонул бы в них.
  #
  # Вход — два готовых профиля, поэтому стадии всё равно, как они получены:
  # из двух файлов, из файла и его же версии с overlay или собраны в тесте.
  module Diff
    COMPARATORS = [Operations, Authorization, Amounts, Statuses, ErrorMap, Webhooks,
                   Idempotence, Fields, Conditions].freeze

    # @param old [IR::ProviderProfile] прежняя версия
    # @param new [IR::ProviderProfile] новая версия
    # @return [Array<Change>] по разделу, адресу и виду; одинаковые изменения
    #   схлопываются: одну и ту же схему могут использовать две операции
    #   контракта, и сказать о ней дважды — не то же, что сказать о двух
    #   изменениях
    def self.call(old, new)
      COMPARATORS.flat_map { |comparator| comparator.new(old, new).call }
                 .uniq.sort_by(&:sort_key)
    end
  end
end
