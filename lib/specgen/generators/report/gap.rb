# frozen_string_literal: true

module SpecGen
  module Generators
    module Report
      # Один непокрытый элемент спецификации: что это, почему не покрыто и в
      # какой корзине непокрытого он лежит.
      #
      #   element     имя элемента в отчёте: операция, поле, код, статус
      #   reason_key  ключ причины под generators.report в locales/*
      #   params      подстановки причины
      #   foreign     элемент принадлежит ресурсу вне границ контракта
      #
      # Зачем корзины. Одна цифра покрытия отвечает на вопрос, которого никто
      # не задавал: «23 %» у Adyen Payout читается как провал разбора, хотя
      # поэлементный замер по десяти спецификациям говорит другое — 59 %
      # непокрытого это посторонние ресурсы самой спецификации (подписки,
      # споры, хранение карт), 33 % — устройство метрики (поле ответа
      # засчитывается, только если контракту есть куда его прочитать), и
      # только 8 % это работа, которую предстоит доделать человеку. Корзина
      # вычисляется из причины, а не назначается вручную: причина у каждого
      # пропуска уже есть, и таблица ниже — единственное место, где решается,
      # что она значит.
      Gap = Struct.new(:element, :reason_key, :params, :foreign, keyword_init: true)

      # Корзины и текст причины.
      class Gap
        # Причина → корзина. Три корзины:
        #
        #   :out_of_contract  вне контракта — ресурс спецификации, которого
        #                     методы контракта не касаются вовсе;
        #   :structural       структурное исключение метрики — элемент, для
        #                     которого места в контракте нет по построению;
        #   :manual           требует ручной работы — единственная корзина,
        #                     адресованная человеку.
        #
        # Причина, которой в таблице нет, попадает в :manual намеренно:
        # новый вид пропуска лучше показать человеку лишний раз, чем спрятать
        # в корзину «это не ваша забота». Полноту таблицы стережёт
        # spec/unit/specgen/generators/report_generator_spec.rb.
        BUCKETS = {
          gap_operation_unmapped: :out_of_contract,
          gap_field_other_operation: :out_of_contract,
          gap_field_optional_skipped: :structural,
          gap_field_required_todo: :manual,
          gap_field_no_accessor: :manual,
          gap_response_role_unknown: :structural,
          gap_response_role_unused: :structural,
          gap_code_range: :structural,
          gap_code_default: :manual,
          gap_status: :manual,
          gap_event: :manual,
          gap_condition_no_check: :manual,
          # Условие, не ставшее проверкой, всегда работа человека: значение
          # собирается в ветке реквизитов, но убедиться, что ограничение
          # спецификации там соблюдено, кроме человека некому.
          gap_condition_in_requisites: :manual,
          gap_condition_cancel_status_restriction: :manual,
          gap_condition_retry_after: :manual,
          gap_condition_rate_limited: :manual,
          gap_condition_idempotency_optional: :manual
        }.freeze

        # Порядок корзин в сводной строке: от чужого к своему, чтобы цифра,
        # ради которой человек читает раздел, оказалась последней.
        ORDER = %i[out_of_contract structural manual].freeze
        # Корзина, которая печатается поимённо и первой.
        MAIN = :manual
        # Остальные — свёрнуто, числом и примерами.
        FOLDED = (ORDER - [MAIN]).freeze
        # Сколько элементов свёрнутой корзины показывать в примерах.
        EXAMPLES = 3

        # @return [Symbol] :out_of_contract, :structural либо :manual
        def bucket
          return :out_of_contract if foreign

          BUCKETS.fetch(reason_key, MAIN)
        end

        # @return [Boolean] пропуск адресован человеку
        def manual?
          bucket == MAIN
        end

        # @return [String] причина по-русски, с подстановками
        def reason
          Texts.t("generators.report.#{reason_key}", **(params || {}))
        end
      end
    end
  end
end
