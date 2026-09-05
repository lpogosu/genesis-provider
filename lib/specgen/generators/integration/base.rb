# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Общее для презентеров INTEGRATION.md: контекст сервиса (профиль,
      # справочники, имена), презентеры сервиса, из которых документ берёт
      # те же данные, что и код, и тексты стадии генерации.
      #
      # Презентер документа никогда не считает то, что уже посчитал
      # презентер сервиса: таблица статусов — это Service::Tables#status_mappings,
      # пересчёт границ суммы — Service::Precheck#description, параметры
      # подписи — Service::Signature#value. Так документ совпадает с кодом по
      # построению, а не по совпадению.
      class Base
        include Markdown

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}] презентеры сервиса
        def initialize(ctx, parts)
          @ctx = ctx
          @parts = parts
        end

        private

        attr_reader :ctx, :parts

        # @param key [String] ключ под generators.integration
        # @return [String]
        def t(key, **params)
          Texts.t("generators.integration.#{key}", **params)
        end

        # @return [String] «подробнее — report.md»
        def report
          t('see_report')
        end

        # @return [IR::ProviderProfile]
        def profile
          ctx.profile
        end

        # @return [Rules::ContractBook]
        def contract
          ctx.contract
        end

        # @param code [Symbol]
        # @return [String] "`failure(:code, 'errors.code')`"
        def failure(code)
          code(ctx.failure(code))
        end

        # @param derived [IR::Derived]
        # @return [String] "задано явно 1.00"
        def label(derived)
          ctx.source_label(derived)
        end

        # @param operation [IR::Operation]
        # @return [String] "`POST /payouts`"
        def endpoint(operation)
          code("#{operation.http_method.to_s.upcase} #{operation.path}")
        end
      end
    end
  end
end
