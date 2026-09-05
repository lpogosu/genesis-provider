# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Один метод сгенерированного класса: имя, параметры, YARD-комментарий и
      # тело строками без отступа. Шаблон печатает сигнатуру и тело, ничего
      # не зная о содержимом.
      #
      #   name    имя метода
      #   params  [{name:, default:}] — как у Rules::MethodSpec#params
      #   doc     строки комментария, уже с «# »
      #   body    строки тела относительно отступа метода
      Method = Struct.new(:name, :params, :doc, :body, keyword_init: true)

      # Сигнатура с пометкой неиспользуемых параметров.
      class Method
        # Параметр, который тело не упоминает, получает префикс «_»: контракт
        # требует его в сигнатуре, а RuboCop — пометки, что он не нужен
        # здесь. Голый `super` передаёт все аргументы, поэтому считается
        # использованием каждого.
        UNUSED_PREFIX = '_'

        # @return [String] "create_request(operation, request_method = 'create')"
        def signature
          return name if params.empty?

          "#{name}(#{params.map { |param| render(param) }.join(', ')})"
        end

        private

        def render(param)
          label = used?(param[:name]) ? param[:name] : "#{UNUSED_PREFIX}#{param[:name]}"
          param[:default] ? "#{label} = #{param[:default]}" : label
        end

        def used?(param_name)
          code = body.reject { |line| line.lstrip.start_with?('#') }.join("\n")
          return true if code.match?(/(?<![\w.])super(?![\w(])/)

          code.match?(/(?<![\w.:@])#{Regexp.escape(param_name)}(?![\w?!])/)
        end
      end
    end
  end
end
