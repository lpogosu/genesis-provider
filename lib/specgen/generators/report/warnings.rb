# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Предупреждения профиля, разложенные по разделам отчёта.
      #
      # Раздел решает код, а не серьёзность: один код — один раздел, иначе
      # читатель искал бы одну и ту же проблему в двух местах. Тест
      # spec/unit/specgen/generators/report_generator_spec.rb следит, что
      # каждый код из IR::Warning::CODES попадает ровно в один раздел, —
      # новый код без раздела делает его красным.
      class Warnings < Base
        # Спецификация противоречит сама себе или своим соседям: enum против
        # примеров, коды ответов у одной операции против другой, проза
        # против структуры, overlay против спецификации. Лечится правкой
        # спецификации, а не настройкой инструмента.
        CONTRADICTIONS = %i[
          undeclared_status_code field_role_conflict units_inconsistent
          status_missing_from_enum error_code_undeclared error_code_unused
          webhook_event_undeclared signature_profile_conflict
          overlay_conflict overlay_target_missing
        ].freeze

        # Инструмент ничего не решал за человека: он сообщает о факте,
        # который читателю всё равно надо увидеть. Действия по ним нет.
        NOTES = %i[
          example_missing server_environment_unknown field_role_unknown
          auth_absent auth_key_in_query contract_gap operation_unmapped
        ].freeze

        # Разделы отчёта, в которые попадают предупреждения.
        SECTIONS = %i[ambiguity contradiction note].freeze

        # У кода есть собственный раздел отчёта — строка справки отсылает
        # туда, чтобы факт не выглядел потерянным.
        CROSS_REFERENCE = { operation_unmapped: 4, contract_gap: 4 }.freeze

        # Справочник, который закрывает этот вид сомнений, когда готового
        # overlay-фрагмента у предупреждения нет.
        BOOKS = {
          field_role_unknown: 'roles', required_field_role_unknown: 'roles',
          field_role_low_confidence: 'roles', field_role_conflict: 'roles',
          operation_unmapped: 'operations', operation_role_ambiguous: 'operations',
          contract_gap: 'operations', status_unmapped: 'statuses',
          status_missing_from_enum: 'statuses', error_action_unknown: 'errors',
          currency_unknown: 'currencies', signature_profile_incomplete: 'signatures',
          signature_profile_conflict: 'signatures', idempotency_header_missing: 'idempotency',
          idempotency_dedup_unclear: 'idempotency', idempotency_header_ambiguous: 'idempotency',
          auth_unknown: 'auth',
          auth_multiple_schemes: 'auth', webhook_event_unmapped: 'statuses',
          condition_unclear: 'conditions'
        }.freeze

        # Сколько элементов показывать в подробной группе и в справке.
        # Adyen Transfers даёт 338 предупреждений, Mollie — 1855: без
        # ограничения отчёт нечитаем, а без числа «ещё K» — нечестен.
        MAX_ITEMS = 20
        MAX_NOTES = 5

        # Одна группа: все предупреждения с одним кодом.
        Group = Struct.new(:code, :total, :items, :hidden, :reference, keyword_init: true)
        # Одно предупреждение в отчёте.
        Item = Struct.new(:path, :message, :action, :fix, :overlay, keyword_init: true)

        # @param code [Symbol] один из IR::Warning::CODES
        # @return [Symbol] один из SECTIONS
        def self.section_for(code)
          return :contradiction if CONTRADICTIONS.include?(code)
          return :note if NOTES.include?(code)

          :ambiguity
        end

        # @return [Array<Group>] раздел 3, по кодам в алфавитном порядке
        def ambiguities
          groups(:ambiguity, MAX_ITEMS)
        end

        # @return [Array<Group>] раздел 5
        def contradictions
          groups(:contradiction, MAX_ITEMS)
        end

        # @return [Array<Group>] раздел 6
        def notes
          groups(:note, MAX_NOTES)
        end

        # @return [Boolean] есть ли хоть одно предупреждение с фрагментом
        def fixable?
          profile.warnings.any?(&:fixable?)
        end

        private

        def groups(section, limit)
          selected = profile.sorted_warnings.select do |warning|
            self.class.section_for(warning.code) == section
          end
          selected.group_by(&:code).sort_by { |code, _list| code.to_s }
                  .map { |code, list| group(code, list, limit) }
        end

        def group(code, list, limit)
          Group.new(code: code, total: list.size, hidden: [list.size - limit, 0].max,
                    items: list.take(limit).map { |warning| item(warning) },
                    reference: CROSS_REFERENCE[code])
        end

        def item(warning)
          Item.new(path: warning.json_path, message: warning.message,
                   action: action(warning.code), fix: fix(warning),
                   overlay: warning.suggested_overlay&.lines&.map(&:chomp))
        end

        # Что инструмент сделал с элементом: текст по коду; для кода, у
        # которого своего текста ещё нет, — общий, лишь бы генерация не
        # падала из-за ненаписанной строки локали.
        def action(code)
          key = "generators.report.action_#{code}"
          Texts.key?(key) ? Texts.t(key) : t('action_default')
        end

        # Чем закрыть, если готового фрагмента overlay нет.
        def fix(warning)
          return nil if warning.fixable?

          book = BOOKS[warning.code]
          book.nil? ? t('fix_spec') : t('fix_book', book: book)
        end
      end
    end
  end
end
