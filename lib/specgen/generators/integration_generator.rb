# frozen_string_literal: true

module SpecGen
  module Generators
    # Артефакт №2: INTEGRATION.md — документация интеграции из
    # templates/INTEGRATION.md.erb. Девять нумерованных разделов; таблицы
    # строятся из тех же презентеров, что константы сервиса.
    class IntegrationGenerator < Base
      TEMPLATE = 'INTEGRATION.md.erb'
      KIND = :integration
      FILE_NAME = 'INTEGRATION.md'

      private

      def file_name
        FILE_NAME
      end

      def view
        Integration::View.new(profile: profile, rules: rules, naming: naming)
      end
    end
  end
end
