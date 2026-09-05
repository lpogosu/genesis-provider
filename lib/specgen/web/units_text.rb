# frozen_string_literal: true

module SpecGen
  module Web
    # Строка о единицах суммы для API — та же, что на экране `analyze`:
    # «minor, x100 (ISO 4217: экспонента RUB 2)».
    #
    # Как и AuthText, это наследник презентера CLI, а не второй способ
    # посчитать множитель: множитель считает IR::Units, фразу — Reporter.
    class UnitsText < Reporter::DerivationLines
      # @return [String] строка о единицах суммы или «единицы не выведены»
      def text
        units_lines.first
      end
    end
  end
end
