# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Раздел 7: что доделать руками, по пунктам и по важности. Сначала то,
      # без чего запрос не уйдёт (TODO в теле запроса), потом заглушки
      # методов, потом всё, что можно проверить после первого прогона.
      #
      # Каждый пункт — действие с именем элемента, а не констатация: список
      # читают, держа рядом сгенерированный файл.
      class Checklist < Base
        # Сколько однотипных пунктов перечислять поимённо.
        MAX_ITEMS = 20

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}]
        def initialize(ctx, parts)
          super
          @fields = SchemaFields.new(ctx)
        end

        # @return [Array<String>] пункты в порядке важности
        def items
          all = payload_items + unmapped_items + signature_route_items + signature_items +
                optional_items + fixture_items + create_items + duplicate_items
          all.map { |item| item.sub(/\A\p{Ll}/, &:upcase) }
        end

        private

        # Обязательное поле тела запроса, которое в код попало с TODO или с
        # ролью ниже порога: без него запрос уйдёт неполным.
        def payload_items
          entries = @fields.of(ctx.create_operation&.request_schema).select do |entry|
            needed?(entry.field) && (entry.field.role.unknown? || ctx.doubtful?(entry.field.role))
          end
          capped(entries.map { |entry| payload_item(entry) })
        end

        def needed?(field)
          field.required? || field.conditionally_required?
        end

        def payload_item(entry)
          field = entry.field
          unless field.role.known?
            return t('todo_field_unknown', path: code(entry.path), evidence: field.role.evidence)
          end

          t('todo_field_doubt', path: code(entry.path), role: code(field.role.value),
                                confidence: label(field.role), evidence: field.role.evidence)
        end

        def unmapped_items
          profile.operations.select(&:unmapped?).map do |operation|
            method = parts[:extras].entries.find { |op, _| op.equal?(operation) }&.last
            t('todo_unmapped', key: code(operation.key), method: code(method&.name))
          end
        end

        # Подпись считается по байтам тела, а process_callback получает уже
        # разобранный JSON: связать одно с другим может только маршрут
        # вебхука. Инструмент за интегратора этого не сделает, поэтому пункт
        # стоит выше остальных подписей.
        def signature_route_items
          return [] if ctx.webhook.nil?

          [t('todo_signature_route', method: code(parts[:signature].public_method.signature),
                                     callback: code(ctx.contract.method_for(:webhook)&.name))]
        end

        def signature_items
          webhook = ctx.webhook
          return [] if webhook.nil? || webhook.signature.nil?

          missing = webhook.signature.missing
          return [] if missing.empty?

          [t('todo_signature', members: missing.map { |member| code(member) }.join(', '))]
        end

        # Необязательное поле тела запроса без роли: по CLAUDE.md оно в
        # payload не попадает, и это решение видно здесь построчно.
        def optional_items
          entries = outgoing_fields.reject { |entry| needed?(entry.field) }
                                   .select { |entry| entry.field.role.unknown? }
          capped(entries.map { |entry| t('todo_optional', path: code(entry.path)) })
        end

        def outgoing_fields
          profile.operations.reject { |operation| operation.role.value == :webhook }
                 .flat_map { |operation| @fields.of(operation.request_schema) }
        end

        # Фикстура, тело которой собрано не из примеров спецификации:
        # проверить значения до подключения к WebMock.
        def fixture_items
          spec_example = Fixtures::Base::SPEC_EXAMPLE
          synthesized = fixtures.reject { |fixture| fixture['source'] == spec_example }
          capped(synthesized.map do |fixture|
            t('todo_fixture', name: code(fixture['name']), source: code(fixture['source']))
          end)
        end

        def fixtures
          [Fixtures::Requests, Fixtures::Responses, Fixtures::Notifications]
            .flat_map { |klass| klass.new(ctx, parts).all }
        end

        # Вторая операция создания: контракт даёт один метод, о второй в коде
        # только комментарий.
        def create_items
          creates = profile.operations_by_role(:create_payout) +
                    profile.operations_by_role(:create_deposit)
          creates.reject { |operation| operation.equal?(ctx.create_operation) }
                 .map { |operation| t('todo_second_create', key: code(operation.key)) }
        end

        # Две проверки одного вида на одну роль дают в check_conditions два
        # одинаковых guard'а: спецификация назвала два поля с одной ролью.
        def duplicate_items
          duplicates.map do |(kind, role), list|
            t('todo_duplicate_check', kind: code(kind), role: code(role),
                                      fields: list.map { |item| code(item.field) }.uniq.join(', '))
          end
        end

        def duplicates
          precheck = parts[:precheck]
          precheck.conditions.group_by { |item| [item.kind, precheck.role_of(item)] }
                  .select { |_key, list| list.size > 1 }
        end

        def capped(items)
          return items if items.size <= MAX_ITEMS

          items.take(MAX_ITEMS) + [t('todo_more', count: items.size - MAX_ITEMS)]
        end
      end
    end
  end
end
