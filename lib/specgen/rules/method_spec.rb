# frozen_string_literal: true

module SpecGen
  module Rules
    # One method of the Provider::BaseService contract, as the dictionary
    # states it. Renders its own signature and call arguments so the ERB
    # templates never spell a method name or a parameter list themselves.
    #
    # It collects its complaints in `problems` instead of raising, and the
    # book drains them into the shared collector with the right JSONPath.
    class MethodSpec
      NAME = /\A[a-z_][a-z0-9_]*[?!]?\z/
      PARAM = /\A[a-z_][a-z0-9_]*\z/

      # @return [String] method name
      attr_reader :name
      # @return [Array<Hash>] each :name and, when it has one, :default
      attr_reader :params
      # @return [Array<String>] operation roles the entry claims to serve
      attr_reader :roles
      # @return [String, nil] what the method returns, for documentation
      attr_reader :returns
      # @return [String, nil] one line on what the method is for
      attr_reader :purpose
      # @return [Array<Array(String, String)>] message and relative path
      attr_reader :problems

      # @param name [Object] key of the entry
      # @param fields [Object] body of the entry
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

      # @return [Boolean] the method calls super before its own work
      def calls_super?
        @fields['calls_super'] == true
      end

      # @return [String] "create_request(operation, request_method = 'create')"
      def signature
        return name if params.empty?

        "#{name}(#{params.map { |param| render(param) }.join(', ')})"
      end

      # @return [String] "operation, request_method", for a super call
      def call_args
        params.map { |param| param[:name] }.join(', ')
      end

      private

      def render(param)
        param[:default] ? "#{param[:name]} = #{param[:default]}" : param[:name]
      end

      def check_name
        return if @name.match?(NAME)

        complain("method name #{@name.inspect} is not a Ruby method name", '')
      end

      def parse_params
        declared = @fields['params']
        return [] if declared.nil?

        unless declared.is_a?(Array)
          complain('params must be an array', '.params')
          return []
        end
        params = declared.each_with_index.filter_map { |item, index| param(item, index) }
        check_order(params)
        params
      end

      def param(item, index)
        at = ".params[#{index}]"
        return complain('parameter must be an object', at) unless item.is_a?(Hash)

        name = item['name'].to_s
        return complain("parameter name #{item['name'].inspect} is not an identifier", at) unless
          name.match?(PARAM)

        { name: name, default: item['default']&.to_s }.freeze
      end

      def check_order(params)
        flags = params.map { |param| !param[:default].nil? }
        return if flags.each_cons(2).none? { |first, second| first && !second }

        complain('parameters with defaults must come last', '.params')
      end

      def complain(message, at)
        @problems << [message, at]
        nil
      end
    end
  end
end
