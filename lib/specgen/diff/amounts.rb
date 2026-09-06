# frozen_string_literal: true

module SpecGen
  module Diff
    # Единицы суммы: валюта, минорные или мажорные единицы, экспонента
    # ISO 4217. Множитель отдельно не сравнивается: он вычисляется из единицы
    # и экспоненты, и сказать о нём значило бы сказать то же самое дважды.
    class Amounts < Area
      # Вид изменения → член IR::Units.
      MEMBERS = { currency_changed: :currency, unit_changed: :unit,
                  exponent_changed: :exponent }.freeze

      private

      def compare
        was = old.units
        now = new.units
        return if was.nil? && now.nil?

        at = address(was, now)
        MEMBERS.each do |kind, member|
          changed(kind, member_of(was, member), member_of(now, member), json_path: at)
        end
      end
    end
  end
end
