# frozen_string_literal: true

module SpecGen
  module Diff
    # Условия взаимодействия: появились, исчезли, сменили значение.
    #
    # Условие связывается с условием по виду, субъекту и адресу: одно и то же
    # ограничение, переехавшее в другое место спецификации, — это другое
    # условие, потому что и предупреждение о нём, и строка отчёта адресуются
    # местом.
    class Conditions < Area
      private

      def compare
        each_element(index(old), index(new)) do |_key, was, now|
          next appeared(now) if was.nil?
          next vanished(was) if now.nil?

          changed(:condition_value_changed, text(was), text(now), json_path: now.json_path,
                                                                  impact: impact_of(now))
        end
      end

      def index(profile)
        profile.conditions.to_h do |condition|
          [[condition.kind, condition.operation, condition.field, condition.json_path], condition]
        end
      end

      def text(condition)
        name = [condition.kind, condition.field].compact.join(' ')
        Change.pair(name, value_of(condition.value))
      end

      # Заголовок идемпотентности сервис отправляет всегда, даже помеченный
      # необязательным: это условие видно только в отчёте.
      def impact_of(condition)
        condition.kind == :idempotency_optional ? :info : :code
      end

      def appeared(condition)
        add(:condition_added, json_path: condition.json_path, after: text(condition),
                              impact: impact_of(condition))
      end

      def vanished(condition)
        add(:condition_removed, json_path: condition.json_path, before: text(condition),
                                impact: impact_of(condition))
      end
    end
  end
end
