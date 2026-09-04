# frozen_string_literal: true

module SpecGen
  module Rules
    # Один метод контракта Provider::BaseService в том виде, в котором его
    # задаёт справочник. Сам выводит свою сигнатуру и аргументы вызова,
    # поэтому ERB-шаблоны никогда не пишут имя метода или список параметров
    # своими руками.
    #
    # Свои жалобы он собирает в `problems`, а не поднимает сразу: книга
    # переливает их в общий сборщик с правильным JSONPath.
    class MethodSpec
      NAME = /\A[a-z_][a-z0-9_]*[?!]?\z/
      PARAM = /\A[a-z_][a-z0-9_]*\z/

      # @return [String] имя метода
      attr_reader :name
      # @return [Array<Hash>] у каждого :name и, если есть, :default
      attr_reader :params
      # @return [Array<String>] роли операций, которые запись берётся
      #   обслуживать
      attr_reader :roles
      # @return [String, nil] что метод возвращает, для документации
      attr_reader :returns
      # @return [String, nil] одна строка о том, зачем метод нужен
      attr_reader :purpose
      # @return [Array<Array(String, String)>] сообщение и относительный путь
      attr_reader :problems

      # @param name [Object] ключ записи
      # @param fields [Object] тело записи
      def initialize(name, fields)
        @name = name.to_s
        @fields = fields.is_a?(Hash) ? fields : {}
        @problems = []
        @roles = Array(@fields['roles']).map(&:to_s)
        @returns = @fields['returns']
        @purpose = @fields['purpose']
        @params = parse_params
        check_name
      end

      # @return [Boolean] метод вызывает super до своей работы
      def calls_super?
        @fields['calls_super'] == true
      end

      # @return [String] "create_request(operation, request_method = 'create')"
      def signature
        return name if params.empty?

        "#{name}(#{params.map { |param| render(param) }.join(', ')})"
      end

      # @return [String] "operation, request_method" — для вызова super
      def call_args
        params.map { |param| param[:name] }.join(', ')
      end

      private

      def render(param)
        param[:default] ? "#{param[:name]} = #{param[:default]}" : param[:name]
      end

      def check_name
        return if @name.match?(NAME)

        complain('bad_name', '', name: @name.inspect)
      end

      def parse_params
        declared = @fields['params']
        return [] if declared.nil?

        unless declared.is_a?(Array)
          complain('params_not_array', '.params')
          return []
        end
        params = declared.each_with_index.filter_map { |item, index| param(item, index) }
        check_order(params)
        params
      end

      def param(item, index)
        at = ".params[#{index}]"
        return complain('param_not_object', at) unless item.is_a?(Hash)

        name = item['name'].to_s
        return complain('bad_param', at, name: item['name'].inspect) unless name.match?(PARAM)

        { name: name, default: item['default']&.to_s }.freeze
      end

      def check_order(params)
        flags = params.map { |param| !param[:default].nil? }
        return if flags.each_cons(2).none? { |first, second| first && !second }

        complain('default_order', '.params')
      end

      # @param key [String] ключ под `rules.method.`
      # @param at [String] путь записи относительно её места в справочнике
      # @return [nil]
      def complain(key, at, **params)
        @problems << [Texts.t("rules.method.#{key}", **params), at]
        nil
      end
    end
  end
end
