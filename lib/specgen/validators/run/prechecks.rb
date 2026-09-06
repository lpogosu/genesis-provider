# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Предпроверки на объекте операции из фикстуры: сначала операция, к
      # которой у спецификации претензий нет, потом та же операция с суммой
      # ниже минимума.
      #
      # Вторая проверка стоит здесь ради пересчёта единиц: спецификация
      # говорит `minimum: 100000` в единицах провайдера, а сравнивается сумма
      # платформы в мажорных. Если пересчёт потерян, отказ придёт не на той
      # границе, и увидеть это можно только вызовом.
      class Prechecks < Base
        KIND = :min_amount

        # @return [Array<Finding>]
        def call
          return [] if spec.nil?

          self.method_name = spec.name
          [baseline, boundary]
        end

        private

        def spec
          return @spec if defined?(@spec)

          built = parts[:precheck].method
          @spec = built && ctx.contract.method_spec(built.name)
        end

        def baseline
          aspect = t('aspect_prechecks')
          result, error = invoke(spec.name, *contract_args(spec))
          return crashed(aspect, error) if error

          verify(aspect) { judge.success(result) }
        end

        # Сумма на единицу ниже границы: ровно то значение, при котором
        # сгенерированный guard обязан сработать.
        def boundary
          condition = minimum
          problem = reason(condition)
          return unchecked(t('aspect_min_amount', value: '—'), problem) if problem

          amount = below(condition)
          aspect = t('aspect_min_amount', value: amount)
          result, error = invoke(spec.name, *contract_args(spec, lowered(amount)))
          return crashed(aspect, error) if error

          verify(aspect) { judge.failure(result, code: code, key: key(condition)) }
        end

        # Почему проверять нечего: спецификация не задала границы, у
        # платформы нет выражения для суммы и в коде остался TODO, либо ниже
        # границы суммы не бывает — при `minimum: 0` отказа не существует, и
        # ждать его значило бы требовать от класса невозможного.
        def reason(condition)
          return t('run_no_condition') if condition.nil?
          return t('run_no_accessor') if parts[:precheck].failure_code(condition).nil?
          return t('run_minimum_zero') unless major_limit(condition).positive?

          nil
        end

        def major_limit(condition)
          Rational(condition.value.value, ctx.profile.units&.multiplier || 1)
        end

        def minimum
          found = parts[:precheck].conditions.find { |item| item.kind == KIND }
          found if found&.value&.value.is_a?(Numeric)
        end

        # Сумма строго ниже границы: на единицу мажорных, а у границы меньше
        # единицы — половина от неё.
        def below(condition)
          major = major_limit(condition)
          lower = major > 1 ? major - 1 : major / 2
          lower.denominator == 1 ? lower.to_i : lower.to_f
        end

        def lowered(amount)
          copy = operation.dup
          copy[amount_field] = amount
          copy
        end

        # Имя поля суммы у объекта операции — то же, которое читает
        # сгенерированный код.
        def amount_field
          Expression.attribute(ctx.accessor(:amount))&.last.to_s
        end

        def code
          ctx.platform.failure_codes.validation
        end

        def key(condition)
          "errors.#{parts[:precheck].failure_code(condition)}"
        end
      end
    end
  end
end
