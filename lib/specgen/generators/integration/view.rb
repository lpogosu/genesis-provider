# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Представление для templates/INTEGRATION.md.erb: шапка и девять
      # разделов. Строится на тех же презентерах, что и сервис
      # (Service::View и его части), поэтому таблицы документа совпадают с
      # константами сервиса по построению.
      class View
        include Markdown

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

        # @return [String] заголовок спецификации или slug
        def provider_title
          @service.provider_title
        end

        # @return [String] slug провайдера
        def provider_slug
          @ctx.naming.slug
        end

        # @return [String]
        def spec_file
          @service.spec_file
        end

        # @return [String]
        def spec_version
          @service.spec_version
        end

        # @return [String]
        def oas_version
          @service.oas_version
        end

        # @return [String] полное имя класса сервиса
        def class_name
          @ctx.full_class_name
        end

        # @return [String]
        def base_class
          @ctx.contract.base_class
        end

        # @return [String] имя файла сервиса
        def service_file
          @ctx.naming.file_name
        end

        # @return [Access] разделы 1 и 2
        def access
          @access ||= Access.new(@ctx, @parts)
        end

        # @return [Methods] раздел 3
        def methods_section
          @methods_section ||= Methods.new(@ctx, @parts)
        end

        # @return [Statuses] раздел 4
        def statuses
          @statuses ||= Statuses.new(@ctx, @parts)
        end

        # @return [Errors] раздел 5
        def errors
          @errors ||= Errors.new(@ctx, @parts)
        end

        # @return [Gateway] раздел 6
        def gateway
          @gateway ||= Gateway.new(@ctx, @parts)
        end

        # @return [SignatureDoc] раздел 7
        def signature
          @signature ||= SignatureDoc.new(@ctx, @parts)
        end

        # @return [Assumptions] раздел 9, допущения проекта
        def assumptions
          @assumptions ||= Assumptions.new(@ctx, @parts)
        end

        # @return [Array<String>] раздел 9, допущения прогона
        def run_assumptions
          @run_assumptions ||= RunAssumptions.new(@ctx, @parts).lines +
                               RunGaps.new(@ctx, @parts).lines
        end

        # @param key [Symbol] смысловой ключ хелпера или метода контракта
        # @return [String] имя в Ruby
        def helper(key)
          @ctx.helper(key)
        end

        # @param role [Symbol] роль операции из IR::Roles::CONTRACT
        # @return [String] имя метода контракта
        def method_for(role)
          @ctx.contract.method_for(role)&.name.to_s
        end

        # @return [String] имя метода предпроверок — единственного метода
        #   контракта без ролей операций
        def precheck_method
          @parts[:precheck].method&.name.to_s
        end

        # @return [String] выражение сырого тела аргумента process_callback
        def callback_body
          @ctx.platform.callback_body || 'payload'
        end

        # @return [String] выражение заголовков аргумента process_callback
        def callback_headers
          @ctx.platform.callback_headers || '{}'
        end

        # @return [String] переменная окружения базового URL
        def base_url_env
          @ctx.base_url_env
        end

        # @param key [String] ключ под generators.integration
        # @return [String]
        def t(key, **params)
          Texts.t("generators.integration.#{key}", **params)
        end
      end
    end
  end
end
