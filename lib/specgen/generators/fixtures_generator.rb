# frozen_string_literal: true

module SpecGen
  module Generators
    # Артефакт №3: fixtures.json — примеры запросов, ответов и уведомлений из
    # templates/fixtures.json.erb.
    #
    # Все три вида обязательны (критерий T5.3). Примеры берутся из `examples`
    # спецификации; там, где их нет, тело собирается из схемы, и поле `source`
    # честно говорит, что придумано, а что прочитано.
    #
    # Проверка результата:
    #   ruby -rjson -e 'JSON.parse(File.read("output/fixtures.json"))'
    class FixturesGenerator < Base
      TEMPLATE = 'fixtures.json.erb'
      KIND = :fixtures
      FILE_NAME = 'fixtures.json'

      private

      def file_name
        FILE_NAME
      end

      def view
        Fixtures::View.new(profile: profile, rules: rules, naming: naming)
      end
    end
  end
end
