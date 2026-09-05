# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Раздел 1: сводка одной таблицей — сколько операций, полей, статусов и
      # предупреждений разобрано. Числа берутся из IR и из презентеров
      # сервиса, а не считаются заново, поэтому строка «22 из 26 скалярных»
      # совпадает с экраном `analyze` и с тем, что напечатано в коде.
      class Stats < Base
        # Источники роли поля в порядке убывания доверия; эвристика делится
        # порогом отчёта на две строки — это разные уровни доверия.
        SOURCES = %i[overlay structural registry heuristic_high heuristic_low].freeze

        # @return [Array<Array(String, String)>] показатель и значение
        def rows
          %w[operations schemas roles unresolved statuses events errors conditions warnings]
            .map { |key| [t("row_#{key}"), send(:"#{key}_value")] }
        end

        # @param artifacts [Array<Artifact>] уже записанные артефакты
        # @return [Array<Array(String, String, String)>] файл, что это, строк
        def artifact_rows(artifacts)
          written = artifacts.map do |artifact|
            [code(artifact.file), t("artifact_#{artifact.kind}"), artifact.lines.to_s]
          end
          written + [[code(ReportGenerator::FILE_NAME), t('artifact_report'), t('artifact_self')]]
        end

        private

        def operations_value
          all = profile.operations
          t('val_operations', total: all.size, contract: all.count(&:contract?),
                              extra: all.count { |op| !op.contract? && !op.unmapped? },
                              unmapped: all.count(&:unmapped?))
        end

        def schemas_value
          t('val_schemas', schemas: profile.schemas.size, fields: fields.size,
                           scalars: scalars.size, containers: fields.size - scalars.size)
        end

        def roles_value
          known = scalars.select { |field| field.role.known? }
          listed = SOURCES.filter_map do |source|
            count = known.count { |field| source_of(field) == source }
            count.zero? ? nil : t("source_#{source}", count: count)
          end
          t('val_roles', known: known.size, scalars: scalars.size, sources: listed.join(', '))
        end

        def unresolved_value
          without = scalars.reject { |field| field.role.known? }
          required = without.count { |field| field.required? || field.conditionally_required? }
          t('val_unresolved', total: without.size, required: required,
                              optional: without.size - required)
        end

        def statuses_value
          mappings = tables.status_mappings
          mapped = mappings.count { |mapping| mapping.internal.known? }
          t('val_pairs', total: mappings.size, mapped: mapped, unmapped: mappings.size - mapped)
        end

        def events_value
          events = tables.events
          mapped = events.count(&:mapped?)
          t('val_pairs', total: events.size, mapped: mapped, unmapped: events.size - mapped)
        end

        def errors_value
          rules = tables.code_rules
          declared = rules.count(&:declared?)
          t('val_errors', total: rules.size, enum: declared, examples: rules.size - declared,
                          http: tables.http_rules.size)
        end

        def conditions_value
          all = profile.conditions
          prose = all.count(&:heuristic?)
          t('val_conditions', total: all.size, formal: all.size - prose, prose: prose)
        end

        def warnings_value
          grouped = profile.warnings_by_severity
          t('val_warnings', total: profile.warnings.size, error: grouped[:error].size,
                            warning: grouped[:warning].size, info: grouped[:info].size)
        end

        # @return [Symbol] один из SOURCES
        def source_of(field)
          role = field.role
          return role.source unless role.source == :heuristic

          ctx.doubtful?(role) ? :heuristic_low : :heuristic_high
        end

        def fields
          @fields ||= profile.schemas.each_value.flat_map(&:fields)
        end

        def scalars
          @scalars ||= fields.reject { |field| Generators::SchemaFields.container?(field) }
        end
      end
    end
  end
end
