# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Общее для презентеров report.md: контекст сервиса (профиль,
      # справочники, имена), презентеры сервиса, из которых видно, что
      # именно попало в код, и тексты стадии генерации.
      #
      # Отчёт не пересчитывает то, что уже посчитали презентеры сервиса и
      # документа: покрытие меряется по тем же таблицам, которые напечатаны
      # в service.rb, — иначе цифра описывала бы не сгенерированный код, а
      # намерение отчёта.
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

        # @param key [String] ключ под generators.report
        # @return [String]
        def t(key, **params)
          Texts.t("generators.report.#{key}", **params)
        end

        # @return [IR::ProviderProfile]
        def profile
          ctx.profile
        end

        # @return [Service::Tables]
        def tables
          parts[:tables]
        end

        # Граница контракта в ресурсах спецификации: её спрашивают оба
        # презентера покрытия, чтобы отличить непокрытое своё от чужого.
        # @return [ContractScope]
        def scope
          @scope ||= ContractScope.new(ctx)
        end

        # @param key [String] ключ измерения
        # @param total [Integer] элементов найдено
        # @param gaps [Array<Gap>] непокрытое поимённо
        # @param out_of_scope [Integer] вычтено из знаменателя второй цифры
        # @return [Dimension]
        def build(key, total, gaps, out_of_scope: 0)
          Dimension.new(key: key, total: total, covered: total - gaps.size, gaps: gaps,
                        out_of_scope: out_of_scope)
        end

        # @param derived [IR::Derived]
        # @return [String] "эвристика 0.54"
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
