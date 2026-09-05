# frozen_string_literal: true

require 'digest'
require 'erb'
require 'fileutils'
require 'json'
require 'openssl'

require_relative 'generators/artifact'
require_relative 'generators/naming'
require_relative 'generators/writer'
require_relative 'generators/markdown'
require_relative 'generators/ruby'
require_relative 'generators/uuid'
require_relative 'generators/base'
require_relative 'generators/service/method'
require_relative 'generators/service/snippets'
require_relative 'generators/service/context'
require_relative 'generators/service/http'
require_relative 'generators/service/payload'
require_relative 'generators/schema_fields'
require_relative 'generators/service/requisites'
require_relative 'generators/service/tables'
require_relative 'generators/service/constants'
require_relative 'generators/service/precheck'
require_relative 'generators/service/creation'
require_relative 'generators/service/polling'
require_relative 'generators/service/callback'
require_relative 'generators/service/signature'
require_relative 'generators/service/authorization'
require_relative 'generators/service/extras'
require_relative 'generators/service/privates'
require_relative 'generators/service/view'
require_relative 'generators/service_generator'
require_relative 'generators/integration/base'
require_relative 'generators/integration/access'
require_relative 'generators/integration/methods'
require_relative 'generators/integration/statuses'
require_relative 'generators/integration/errors'
require_relative 'generators/integration/gateway'
require_relative 'generators/integration/signature_doc'
require_relative 'generators/integration/assumptions'
require_relative 'generators/integration/run_assumptions'
require_relative 'generators/integration/run_gaps'
require_relative 'generators/integration/view'
require_relative 'generators/integration_generator'
require_relative 'generators/fixtures/values'
require_relative 'generators/fixtures/signing'
require_relative 'generators/fixtures/base'
require_relative 'generators/fixtures/requests'
require_relative 'generators/fixtures/responses'
require_relative 'generators/fixtures/notifications'
require_relative 'generators/fixtures/view'
require_relative 'generators/fixtures_generator'
require_relative 'generators/report/base'
require_relative 'generators/report/dimension'
require_relative 'generators/report/coverage_fields'
require_relative 'generators/report/coverage'
require_relative 'generators/report/warnings'
require_relative 'generators/report/stats'
require_relative 'generators/report/operations'
require_relative 'generators/report/checklist'
require_relative 'generators/report/checks'
require_relative 'generators/report/view'
require_relative 'generators/report_generator'
require_relative 'generators/runner'

module SpecGen
  # Стадия генерации: профиль провайдера → артефакты в каталоге вывода.
  #
  # Один генератор — один артефакт и один ERB-шаблон в templates/. Шаблон
  # читает только IR через объект-представление (Generators::Service::View и
  # его презентеры) и никогда не заглядывает в спецификацию: если шаблону
  # чего-то не хватает, не хватает поля в IR. Имена методов контракта,
  # хелперов и внутренних статусов шаблон берёт из rules/contract.yml.
  #
  # Генерация не блокируется никогда: файлы пишутся при любых
  # предупреждениях, а там, где IR не уверен, в код идёт лучший кандидат и
  # TODO с уверенностью и альтернативами. Единственный отказ — нечитаемая
  # спецификация, и его даёт SpecLoader задолго до этой стадии.
  module Generators
    # @param profile [IR::ProviderProfile] заполненный анализаторами
    # @param rules [Rules::Registry] справочники
    # @param document [SpecLoader::Document] спецификация, из которой выведен
    #   профиль: по ней стадия проверки сверяет записанные фикстуры со
    #   схемами запросов и ответов
    # @param options [Hash] опции CLI (:output, :provider), ключи строками
    #   или символами
    # @return [Array<Artifact>] записанные артефакты в порядке генерации
    # @raise [GenerationError] шаблон не отрендерился или файл не записался
    def self.call(profile:, rules:, document: nil, options: {})
      Runner.new(profile: profile, rules: rules, document: document, options: options).call
    end
  end
end
