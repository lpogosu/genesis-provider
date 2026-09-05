# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 9, часть первая: допущения проекта из rules/assumptions.yml и
      # раздела platform контракта. Генератор не читает docs/: источник
      # истины — справочник, журнал для людей — docs/ASSUMPTIONS.md.
      class Assumptions < Base
        # Роли, чьи выражения показываются как примеры раздела platform.
        SAMPLE_ROLES = %i[amount external_id provider_operation_id].freeze

        # @return [String] почему контракт — допущение, из rules/contract.yml
        def contract_line
          contract.assumption.to_s.gsub(/\s*\n\s*/, ' ').strip
        end

        # @return [Array<String>] по строке на действующее допущение проекта
        def project_lines
          ctx.rules.assumptions.documented.map do |item|
            t('assumption_line', id: item.id, text: item.text, source: item.source,
                                 affects: item.affects)
          end
        end

        # @return [String] выражения платформы и их источник
        def platform_line
          platform = ctx.platform
          examples = SAMPLE_ROLES.filter_map { |role| platform.accessor(role) }
          examples << platform.lookup(:provider_operation_id, '…')
          examples << platform.callback_body
          t('platform_line', source: platform.source.to_s, examples: codes(examples.compact))
        end
      end
    end
  end
end
