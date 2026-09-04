# frozen_string_literal: true

module SpecGen
  module Rules
    # Контракт Provider::BaseService как данные.
    #
    # Реального базового класса нам не выдали, поэтому контракт здесь —
    # задокументированное допущение: имена методов, списки параметров, имена
    # хелперов, внутренние статусы и смысл `request_method`. Держать его в
    # справочнике, а не в ERB-шаблонах, — и есть смысл этого файла: когда
    # эксперты поправят контракт, мы правим этот файл и перегенерируем, а ни
    # один шаблон не трогаем.
    #
    # Каждый метод сам привязывает себя к ролям операций, которые он
    # обслуживает, поэтому IR::Roles::CONTRACT остаётся покрытым, а lib/ так
    # и не узнаёт ни одного имени метода.
    class ContractBook < Book
      FILE = 'contract.yml'
      # Хелперы, которые генераторы просят по смыслу. Справочник даёт имя
      # каждого в Ruby, поэтому переименованный хелпер — правка данных.
      HELPERS = %i[success failure client auth_headers approve_operation
                   reject_operation].freeze
      CLASS_NAME = /\A[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*\z/

      # @return [String, nil] класс, от которого наследует сгенерированный
      #   сервис
      attr_reader :base_class
      # @return [String, nil] почему этот контракт — допущение
      attr_reader :assumption
      # @return [Array<Symbol>] внутренние статусы так, как их знает IR
      attr_reader :internal_statuses
      # @return [String, nil] что означает request_method, для документации
      attr_reader :request_method_semantics
      # @return [Array<String>] значения request_method, встречающиеся на
      #   практике
      attr_reader :request_method_values
      # @return [Symbol, nil] :major или :minor — единица operation.amount
      attr_reader :amount_unit

      # @param name [String, Symbol]
      # @return [MethodSpec, nil]
      def method_spec(name)
        @methods[name.to_s]
      end

      # @param role [Symbol] роль операции из IR::Roles::CONTRACT
      # @return [MethodSpec, nil] метод, который её обслуживает
      def method_for(role)
        method_spec(@roles[role])
      end

      # @return [Array<String>] имена методов, в порядке справочника
      def method_names
        @methods.keys
      end

      # @param key [Symbol] смысловой ключ хелпера, один из HELPERS
      # @return [String, nil] имя метода Ruby, который надо вызвать
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
        @base_class = text(data['base_class'], noun(:base_class), path('base_class'))
        @assumption = text(data['assumption'], noun(:assumption), path('assumption'))
        return if @base_class.nil? || @base_class.match?(CLASS_NAME)

        fault('contract.bad_class', path('base_class'), name: @base_class.inspect)
      end

      def load_methods
        @methods = {}
        @roles = {}
        section('methods').each { |name, body| add_method(name, body) }
        fault('contract.no_methods', path('methods')) if @methods.empty?
        @methods.freeze
      end

      def add_method(name, body)
        at = path('methods', name)
        spec = MethodSpec.new(name, mapping(body, noun(:method_body, name: name), at))
        spec.problems.each { |message, suffix| complain(message, "#{at}#{suffix}") }
        spec.roles.each_with_index { |role, index| bind(spec.name, role, "#{at}.roles[#{index}]") }
        @methods[spec.name] = spec
      end

      def bind(method_name, role, at)
        symbol = symbol_in(role, IR::Roles::CONTRACT, noun(:operation_role), at)
        return if symbol.nil?

        owner = @roles[symbol]
        return @roles[symbol] = method_name if owner.nil?

        fault('contract.role_taken', at, role: symbol, method: owner)
      end

      def load_helpers
        @helpers = {}
        section('helpers').each { |key, body| add_helper(key, body) }
        report_missing_helpers
        @helpers.freeze
      end

      def report_missing_helpers
        missing = HELPERS - @helpers.keys
        return if missing.empty?

        fault('contract.helpers_missing', path('helpers'), helpers: missing.join(', '))
      end

      def add_helper(key, body)
        at = path('helpers', key)
        fields = mapping(body, noun(:helper_body, key: key), at)
        spec = MethodSpec.new(fields.fetch('method', key), fields)
        spec.problems.each { |message, suffix| complain(message, "#{at}#{suffix}") }
        @helpers[key.to_sym] = { method: spec.name, params: spec.params,
                                 purpose: fields['purpose'], example: fields['example'] }.freeze
      end

      def load_semantics
        @internal_statuses = load_internal_statuses
        semantics = mapping(data['request_method'], noun(:request_method), path('request_method'),
                            required: false)
        @request_method_semantics = semantics['semantics']
        @request_method_values = string_list(semantics['known_values'],
                                             noun(:list, key: 'known_values'),
                                             path('request_method', 'known_values'))
        @amount_unit = load_amount_unit
      end

      def load_amount_unit
        at = path('operation', 'amount_unit')
        operation = mapping(data['operation'], noun(:operation_section), path('operation'),
                            required: false)
        symbol_in(operation['amount_unit'], IR::Units::UNITS, noun(:amount_unit), at)
      end

      def load_internal_statuses
        at = path('internal_statuses')
        listed = string_list(data['internal_statuses'], noun(:list, key: 'internal_statuses'), at)
        statuses = listed.each_with_index.filter_map do |status, index|
          symbol_in(status, IR::Roles::INTERNAL_STATUS, noun(:internal_status), "#{at}[#{index}]")
        end
        return statuses if statuses.sort == IR::Roles::INTERNAL_STATUS.sort

        fault('contract.statuses_mismatch', at, statuses: IR::Roles::INTERNAL_STATUS.join(', '))
        statuses
      end

      def report_uncovered_roles
        missing = IR::Roles::CONTRACT - @roles.keys
        return if missing.empty?

        fault('contract.uncovered_roles', path('methods'), roles: missing.join(', '))
      end
    end
  end
end
