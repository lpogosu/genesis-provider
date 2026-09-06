# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Скалярные константы сервиса: множитель суммы, код валюты, действие по
      # умолчанию, код дедупликации, ключ идемпотентности, разрешённые для
      # отмены статусы и константы подписи.
      #
      # Каждая — с комментарием об источнике: множитель ссылается на
      # экспоненту ISO 4217, валюта — на то место спецификации, откуда взят
      # код, невыведенное значение получает TODO. Платформа валюту не
      # сообщает (эксперты кейса, 5 сентября 2026, вопрос 18), поэтому
      # CURRENCY — константа сервиса, а не поле операции.
      class Constants
        # Ширина комментария на уровне тела класса.
        WIDTH = Ruby::WIDTH - 4

        # @param ctx [Context]
        # @param parts [Hash{Symbol => Object}] signature и extras: их
        #   константы печатаются в том же списке
        def initialize(ctx, parts)
          @ctx = ctx
          @parts = parts
        end

        # @return [Array<Array(String, String, Array<String>)>] имя, литерал,
        #   комментарии над ней
        def all
          list = [amount, *currency, ['DEFAULT_ERROR_ACTION', default_error_action, []]]
          list << ['DEDUP_STATUS', Ruby.number(dedup_status), []] if dedup_status
          list.concat(idempotency)
          list << ['CANCELLABLE_STATUSES', "#{Ruby.literal(cancellable)}.freeze", []] if cancellable
          list + (@ctx.profile.webhooks.any? ? @parts[:signature].constants : [])
        end

        private

        def default_error_action
          Ruby.sym(@ctx.rules.errors.default_action)
        end

        def dedup_status
          idempotency = @ctx.profile.idempotency
          idempotency&.dedup? ? idempotency.conflict_status.value : nil
        end

        def cancellable
          @parts[:extras].cancellable_statuses
        end

        def amount
          units = @ctx.profile.units
          return ['AMOUNT_MULTIPLIER', units.multiplier.to_s, units_comment(units)] if units&.known?

          # Обоснование берётся у члена, которого не хватило, а не у
          # выведенного: иначе комментарий говорит «единицы не выведены
          # (type: integer -> минорные единицы)» и противоречит сам себе.
          evidence = units.nil? ? @ctx.t('units_none') : units.blocker.evidence
          text = @ctx.t('units_unknown', evidence: evidence)
          ['AMOUNT_MULTIPLIER', '1', Ruby.comment(text, width: WIDTH, prefix: '# TODO: ')]
        end

        # Валюта запроса — константа, а не поле операции. Не выведена —
        # константы нет, и поле тела запроса получает TODO там, где оно
        # печатается.
        def currency
          code = @ctx.currency
          return [] if code.nil? || !currency_sent?

          text = @ctx.t('currency_comment', evidence: @ctx.profile.units.currency.evidence)
          [[Context::CURRENCY_CONSTANT, Ruby.str(code), Ruby.comment(text, width: WIDTH)]]
        end

        # @return [Boolean] хоть одно тело запроса несёт поле с ролью валюты
        def currency_sent?
          schemas = @ctx.profile.operations.reject { |op| op.role.value == :webhook }
                        .filter_map(&:request_schema).uniq
          schemas.any? { |name| @ctx.role_path(name, :currency) }
        end

        def units_comment(units)
          text = @ctx.t('units_comment', unit: units.unit.value, evidence: units.exponent.evidence,
                                         currency: units.currency.value.to_s)
          Ruby.comment(text, width: WIDTH)
        end

        def idempotency
          idempotency = @ctx.profile.idempotency
          return [] unless idempotency&.supported?

          header = @ctx.t('idempotency_comment', evidence: idempotency.header.evidence)
          [['IDEMPOTENCY_HEADER', Ruby.str(idempotency.header.value),
            Ruby.comment(header, width: WIDTH)],
           ['IDEMPOTENCY_NAMESPACE', Ruby.str(@ctx.rules.idempotency.namespace),
            Ruby.comment(@ctx.t('namespace_comment'), width: WIDTH)]]
        end
      end
    end
  end
end
