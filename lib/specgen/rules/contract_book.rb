# frozen_string_literal: true

module SpecGen
  module Rules
    # The Provider::BaseService contract as data.
    #
    # The real base class was never handed to us, so the contract here is a
    # documented assumption: method names, parameter lists, helper names,
    # internal statuses and the meaning of `request_method`. Keeping it in a
    # dictionary rather than in the ERB templates is the point - when the
    # experts correct the contract we change this file and regenerate, and no
    # template is touched.
    #
    # Each method binds itself to the operation roles it serves, so
    # IR::Roles::CONTRACT stays covered without lib/ ever knowing a method
    # name.
    class ContractBook < Book
      FILE = 'contract.yml'
      # The helpers the generators call for by meaning. The dictionary gives
      # the Ruby name of each, so a renamed helper is a data change.
      HELPERS = %i[success failure client auth_headers approve_operation
                   reject_operation].freeze
      CLASS_NAME = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/

      # @return [String, nil] class the generated service inherits from
      attr_reader :base_class
      # @return [String, nil] why this contract is an assumption
      attr_reader :assumption
      # @return [Array<Symbol>] the internal statuses, as IR knows them
      attr_reader :internal_statuses
      # @return [String, nil] what request_method means, for the docs
      attr_reader :request_method_semantics
      # @return [Array<String>] request_method values seen in practice
      attr_reader :request_method_values
      # @return [Symbol, nil] :major or :minor, the unit of operation.amount
      attr_reader :amount_unit

      # @param name [String, Symbol]
      # @return [MethodSpec, nil]
      def method_spec(name)
        @methods[name.to_s]
      end

      # @param role [Symbol] operation role from IR::Roles::CONTRACT
      # @return [MethodSpec, nil] the method that serves it
      def method_for(role)
        method_spec(@roles[role])
      end

      # @return [Array<String>] method names, in dictionary order
      def method_names
        @methods.keys
      end

      # @param key [Symbol] semantic helper key, one of HELPERS
      # @return [String, nil] the Ruby method name to call
      def helper(key)
        @helpers.dig(key.to_sym, :method)
      end

      # @param key [Symbol]
      # @return [Hash, nil] :method, :params, :purpose, :example
      def helper_spec(key)
        @helpers[key.to_sym]
      end

      private

      def build
        load_class
        load_methods
        load_helpers
        load_semantics
        report_uncovered_roles
      end

      def load_class
        @base_class = text(data['base_class'], 'base class', path('base_class'))
        @assumption = text(data['assumption'], 'assumption note', path('assumption'))
        return if @base_class.nil? || @base_class.match?(CLASS_NAME)

        complain("base class #{@base_class.inspect} is not a Ruby constant path",
                 path('base_class'))
      end

      def load_methods
        @methods = {}
        @roles = {}
        section('methods').each { |name, body| add_method(name, body) }
        complain('at least one method is required', path('methods')) if @methods.empty?
        @methods.freeze
      end

      def add_method(name, body)
        at = path('methods', name)
        spec = MethodSpec.new(name, mapping(body, "method #{name}", at))
        spec.problems.each { |message, suffix| complain(message, "#{at}#{suffix}") }
        spec.roles.each_with_index { |role, index| bind(spec.name, role, "#{at}.roles[#{index}]") }
        @methods[spec.name] = spec
      end

      def bind(method_name, role, at)
        symbol = symbol_in(role, IR::Roles::CONTRACT, 'operation role', at)
        return if symbol.nil?

        owner = @roles[symbol]
        return @roles[symbol] = method_name if owner.nil?

        complain("operation role #{symbol} is already served by #{owner}", at)
      end

      def load_helpers
        @helpers = {}
        section('helpers').each { |key, body| add_helper(key, body) }
        missing = HELPERS - @helpers.keys
        complain("helpers missing: #{missing.join(', ')}", path('helpers')) unless missing.empty?
        @helpers.freeze
      end

      def add_helper(key, body)
        at = path('helpers', key)
        fields = mapping(body, "helper #{key}", at)
        spec = MethodSpec.new(fields.fetch('method', key), fields)
        spec.problems.each { |message, suffix| complain(message, "#{at}#{suffix}") }
        @helpers[key.to_sym] = { method: spec.name, params: spec.params,
                                 purpose: fields['purpose'], example: fields['example'] }.freeze
      end

      def load_semantics
        @internal_statuses = load_internal_statuses
        semantics = mapping(data['request_method'], 'request_method', path('request_method'),
                            required: false)
        @request_method_semantics = semantics['semantics']
        @request_method_values = string_list(semantics['known_values'], 'known values',
                                             path('request_method', 'known_values'))
        @amount_unit = load_amount_unit
      end

      def load_amount_unit
        at = path('operation', 'amount_unit')
        operation = mapping(data['operation'], 'operation', path('operation'), required: false)
        symbol_in(operation['amount_unit'], IR::Units::UNITS, 'amount unit', at)
      end

      def load_internal_statuses
        at = path('internal_statuses')
        listed = string_list(data['internal_statuses'], 'internal statuses', at)
        statuses = listed.each_with_index.filter_map do |status, index|
          symbol_in(status, IR::Roles::INTERNAL_STATUS, 'internal status', "#{at}[#{index}]")
        end
        return statuses if statuses.sort == IR::Roles::INTERNAL_STATUS.sort

        complain("internal statuses must be exactly #{IR::Roles::INTERNAL_STATUS.join(', ')}", at)
        statuses
      end

      def report_uncovered_roles
        missing = IR::Roles::CONTRACT - @roles.keys
        return if missing.empty?

        complain("no method serves #{missing.join(', ')}; add a `roles:` list to the method " \
                 'that handles it', path('methods'))
      end
    end
  end
end
