# frozen_string_literal: true

module SpecGen
  module IR
    # Одно условие взаимодействия с провайдером: что сервис обязан соблюсти
    # или учесть помимо формы запроса — пауза перед повтором, минимальная
    # сумма, допустимые статусы для отмены, длина и формат идентификаторов.
    #
    # Это не условная обязательность поля (RequiredWhen) и не правило по
    # ошибке (ErrorRule): условие — факт о границах взаимодействия, который
    # INTEGRATION.md перечисляет списком, а сгенерированный сервис проверяет
    # до запроса или учитывает после ответа. Виды закрыты словарём KINDS.
    #
    #   kind       один из KINDS
    #   operation  Operation#key, к которому относится условие, или nil,
    #              если оно про поле и действует везде, где поле есть
    #   field      имя поля, если условие про поле, иначе nil
    #   value      Derived — само ограничение как написано в спецификации:
    #              число для min_amount и field_max_length, строка для
    #              field_pattern, список для field_enum и
    #              cancel_status_restriction, код ответа для retry_after,
    #              имя заголовка для idempotency_optional, true для
    #              rate_limited. Пересчёт единиц — дело генератора вместе с
    #              Units: анализаторы независимы
    #   json_path  элемент спецификации, из которого прочитано условие
    Condition = Struct.new(:kind, :operation, :field, :value, :json_path, keyword_init: true)

    # Словарь видов и проверки Condition.
    class Condition
      include Node

      # Закрытый словарь видов условий.
      #
      #   retry_after                ответ объявляет заголовок паузы до повтора
      #   rate_limited               операция объявляет ответ 429
      #   min_amount / max_amount    границы суммы в единицах провайдера
      #   field_max_length           предел длины поля с ролью
      #   field_pattern              формат поля с ролью
      #   field_enum                 допустимые значения поля с ролью
      #   cancel_status_restriction  статусы, в которых отмена возможна
      #   idempotency_optional       заголовок идемпотентности объявлен
      #                              необязательным
      KINDS = %i[
        retry_after rate_limited min_amount max_amount field_max_length field_pattern field_enum
        cancel_status_restriction idempotency_optional
      ].freeze

      # @param kind [Symbol] один из KINDS
      # @param value [Derived]
      # @param operation [String, nil]
      # @param field [String, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(kind:, value:, operation: nil, field: nil, json_path: nil)
        Node.assert_member!(KINDS, kind, 'вид условия')
        Node.assert_derived!(value, 'значение условия')
        super
      end

      # @return [Boolean] условие относится к полю, а не к операции целиком
      def field?
        !field.nil?
      end

      # @return [Boolean] условие прочитано из прозы, а не из ключевых слов
      def heuristic?
        value.source == :heuristic
      end
    end
  end
end
