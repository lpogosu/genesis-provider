# frozen_string_literal: true

require_relative 'reporter/format'
require_relative 'reporter/derivation_lines'
require_relative 'reporter/operation_lines'
require_relative 'reporter/schema_lines'
require_relative 'reporter/summary'

module SpecGen
  # Последняя стадия конвейера: говорит человеку, что выведено и что нет.
  #
  # В этом пространстве имён два вывода. `Summary` — экран, который печатает
  # `integrate analyze`: одна строка на факт, рядом с каждым выведенным
  # значением его источник и уверенность. report.md, файл, который пишет
  # конвейер генерации, будет собран из того же профиля по тем же правилам
  # форматирования. Ни один из них не читает спецификацию: единственный вход —
  # профиль, поэтому показать нельзя ничего, чего не увидят генераторы.
  module Reporter
  end
end
