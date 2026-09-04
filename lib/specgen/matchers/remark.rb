# frozen_string_literal: true

module SpecGen
  module Matchers
    # Предупреждение, которое матчеры сформулировали, но записать не могут:
    # профилем владеет анализатор. Reader получает Remark вместе с решением,
    # добавляет JSONPath поля и передаёт анализатору как Note.
    #
    #   code               один из IR::Warning::CODES
    #   message            фраза для человека
    #   severity           :warning у обязательного поля — без него запрос не
    #                      уйдёт; :info у необязательного — оно будет пропущено
    #   suggested_overlay  фрагмент overlay с x-specgen-role, закрепляющий роль
    Remark = Struct.new(:code, :message, :severity, :suggested_overlay, keyword_init: true)
  end
end
