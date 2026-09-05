# frozen_string_literal: true

module SpecGen
  module Generators
    # Артефакт №1: `<provider>_service.rb` — класс по контракту
    # Provider::BaseService из templates/service.rb.erb.
    #
    # Проверка результата (её же берёт стадия Validators):
    #   ruby -c output/<provider>_service.rb
    #   bundle exec rubocop --config config/rubocop_generated.yml output/<provider>_service.rb
    class ServiceGenerator < Base
      TEMPLATE = 'service.rb.erb'
      KIND = :service

      private

      def file_name
        naming.file_name
      end

      def view
        Service::View.new(profile: profile, rules: rules, naming: naming)
      end
    end
  end
end
