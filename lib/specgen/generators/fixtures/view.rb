# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Представление для templates/fixtures.json.erb: весь документ собран
      # здесь, шаблон только печатает его как JSON.
      #
      # Строится на тех же презентерах, что и сервис (Service::View и его
      # части), поэтому заголовки, ключ идемпотентности, подпись и ожидаемые
      # статусы в фикстурах совпадают с кодом по построению, а не по
      # совпадению.
      class View
        # Ключи верхнего уровня в фиксированном порядке: сначала о ком
        # документ, потом три вида фикстур.
        INDENT = 2

        # @param profile [IR::ProviderProfile]
        # @param rules [Rules::Registry]
        # @param naming [Naming]
        def initialize(profile:, rules:, naming:)
          @service = Service::View.new(profile: profile, rules: rules, naming: naming)
          @ctx = @service.context
          @parts = @service.parts.merge(view: @service)
        end

        # @return [Binding] контекст рендеринга ERB
        def template_binding
          binding
        end

        # @return [String] документ целиком, отступ два пробела, UTF-8 как есть
        def json
          ::JSON.pretty_generate(document)
        end

        # @return [Hash] fixtures.json как данные
        def document
          { 'provider' => @ctx.naming.slug, 'spec' => spec, 'base_url' => @ctx.sandbox_url,
            'credentials' => requests.credentials, 'requests' => requests.all,
            'responses' => responses.all, 'notifications' => notifications.all }
        end

        private

        # @return [Hash] откуда сгенерированы фикстуры
        def spec
          info = @ctx.profile.info
          { 'file' => info&.spec_file, 'version' => info&.spec_version,
            'openapi' => info&.oas_version }
        end

        def requests
          @requests ||= Requests.new(@ctx, @parts)
        end

        def responses
          @responses ||= Responses.new(@ctx, @parts)
        end

        def notifications
          @notifications ||= Notifications.new(@ctx, @parts)
        end
      end
    end
  end
end
