# frozen_string_literal: true

module SpecGen
  # Композитный матчер ролей полей по подходу COMA (Rahm & Bernstein 2001;
  # Do & Rahm 2002): несколько независимых матчеров, веса, агрегация, порог.
  #
  # Имён полей у провайдеров бесконечно много, ролей в платёжной области
  # шестнадцать (IR::Roles::FIELD). Каждый матчер смотрит на своё — имя,
  # тип, ограничения, расположение — и голосует за роли баллом в [0, 1];
  # Composite складывает голоса с весами из rules/roles.yml и ранжирует
  # кандидатов, Assigner превращает ранжирование в IR::Derived, разводит
  # конфликты внутри одной схемы и формулирует предупреждения. Ни одного
  # имени поля в этом пространстве имён нет: вся лексика — данные
  # справочника.
  #
  # Порог решает не «присваивать ли роль», а «попадёт ли решение в отчёт»:
  # ниже порога роль всё равно получает лучший кандидат, но с предупреждением
  # и реальной уверенностью; без роли поле остаётся только тогда, когда за
  # него не проголосовал ни один опознающий матчер.
  #
  # Общий компонент для анализаторов, а не анализатор: SchemaAnalyzer и
  # OperationAnalyzer проставляют роли полям и параметрам через него в тот
  # момент, когда читают их из документа, — так ни один анализатор не читает
  # то, что записал другой.
  module Matchers
  end
end

require_relative 'matchers/subject'
require_relative 'matchers/vote'
require_relative 'matchers/levenshtein'
require_relative 'matchers/name_matcher'
require_relative 'matchers/type_matcher'
require_relative 'matchers/constraint_matcher'
require_relative 'matchers/structure_matcher'
require_relative 'matchers/candidate'
require_relative 'matchers/composite'
require_relative 'matchers/remark'
require_relative 'matchers/decision'
require_relative 'matchers/remarks'
require_relative 'matchers/assigner'
