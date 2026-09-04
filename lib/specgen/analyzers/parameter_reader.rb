# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Параметры одной операции, включая унаследованные.
    #
    # OpenAPI объявляет параметры в двух местах: на path item, откуда их
    # наследует каждая операция этого пути, и на самой операции, которая
    # переопределяет унаследованный параметр с тем же именем и местом. Не
    # заметить это наследование — потерять идентификатор в пути у каждого
    # аккуратно написанного `GET /payouts/{id}`, поэтому оно смоделировано
    # здесь, а не оставлено каждому вызывающему.
    #
    # Параметр несёт роль так же, как поле, и получает её тем же
    # Matchers::Assigner — всем параметрам операции разом, чтобы два
    # параметра с одной ролью были замечены. Без assigner (так читают
    # анализаторы, которым роли не нужны) роль остаётся невыведенной:
    # выдумывание роли в двух местах привело бы к расхождению между ними.
    class ParameterReader
      # @return [Array<Array(String, String)>] сообщение и JSONPath каждого
      #   параметра, о котором вызывающий должен предупредить
      attr_reader :problems
      # @return [Array<Note>] замечания матчеров о ролях параметров
      attr_reader :notes

      # @param shared [Object] `parameters` у path item
      # @param own [Object] `parameters` у операции
      # @param shared_path [String] JSONPath списка у path item
      # @param own_path [String] JSONPath списка у операции
      # @param assigner [Matchers::Assigner, nil] матчер ролей; nil — роли
      #   остаются невыведенными
      def initialize(shared:, own:, shared_path:, own_path:, assigner: nil)
        @shared = shared
        @own = own
        @shared_path = shared_path
        @own_path = own_path
        @assigner = assigner
        @problems = []
        @notes = []
        @items = {}
      end

      # Унаследованные параметры сохраняют своё место; переопределение
      # занимает место унаследованного, а параметр, объявленный только
      # операцией, добавляется в конец.
      # @return [Array<IR::Parameter>]
      def call
        merged = read(@shared, @shared_path).to_h { |parameter| [key_of(parameter), parameter] }
        read(@own, @own_path).each { |parameter| merged[key_of(parameter)] = parameter }
        assign_roles(merged.values)
      end

      private

      # @return [Array<IR::Parameter>] те же параметры, с ролями
      def assign_roles(parameters)
        return parameters if @assigner.nil? || parameters.empty?

        subjects = parameters.map do |parameter|
          RoleSubjects.parameter(parameter, @items.fetch(key_of(parameter)))
        end
        @notes.concat(RoleSubjects.assign(@assigner, parameters, subjects))
        parameters
      end

      def key_of(parameter)
        [parameter.name, parameter.location]
      end

      def read(list, at)
        return [] if list.nil?

        unless list.is_a?(Array)
          problem(Texts.t('analyzers.common.must_be_list', key: 'parameters'), at)
          return []
        end

        list.each_with_index.filter_map { |item, index| parameter(item, "#{at}[#{index}]") }
      end

      def parameter(item, at)
        return problem(Texts.t('analyzers.parameter.shape'), at) unless item.is_a?(Hash)

        name = item['name']
        location = location_of(item['in'])
        return problem(Texts.t('analyzers.parameter.name_missing'), at) if bad?(name, location)

        build(item, name, location, at)
      end

      def build(item, name, location, at)
        schema = item['schema'].is_a?(Hash) ? item['schema'] : {}
        @items[[name, location]] = item
        IR::Parameter.new(name: name, location: location, role: pending_role,
                          required: location == :path || item['required'] == true,
                          type: schema['type'], format: schema['format'],
                          description: item['description'],
                          example: item.key?('example') ? item['example'] : schema['example'],
                          json_path: at)
      end

      def bad?(name, location)
        !name.is_a?(String) || name.strip.empty? || location.nil?
      end

      def location_of(value)
        location = value.to_s.downcase.to_sym
        IR::Parameter::LOCATIONS.include?(location) ? location : nil
      end

      # Роль до матчеров; с assigner её заменит Matchers::Assigner.
      def pending_role
        IR::Derived.unknown(evidence: Texts.t('analyzers.parameter.role_pending'))
      end

      # @return [nil] чтобы filter_map выбросил описанный параметр
      def problem(message, at)
        @problems << [message, at]
        nil
      end
    end
  end
end
