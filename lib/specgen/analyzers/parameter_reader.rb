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
    # Роли здесь намеренно не сопоставляются. Параметр несёт роль так же,
    # как поле, но сопоставление имён с ролями — работа матчеров полей, а
    # выдумывание роли в двух местах привело бы к расхождению между ними.
    class ParameterReader
      # @return [Array<Array(String, String)>] сообщение и JSONPath каждого
      #   параметра, о котором вызывающий должен предупредить
      attr_reader :problems

      # @param shared [Object] `parameters` у path item
      # @param own [Object] `parameters` у операции
      # @param shared_path [String] JSONPath списка у path item
      # @param own_path [String] JSONPath списка у операции
      def initialize(shared:, own:, shared_path:, own_path:)
        @shared = shared
        @own = own
        @shared_path = shared_path
        @own_path = own_path
        @problems = []
      end

      # Унаследованные параметры сохраняют своё место; переопределение
      # занимает место унаследованного, а параметр, объявленный только
      # операцией, добавляется в конец.
      # @return [Array<IR::Parameter>]
      def call
        merged = read(@shared, @shared_path).to_h { |parameter| [key_of(parameter), parameter] }
        read(@own, @own_path).each { |parameter| merged[key_of(parameter)] = parameter }
        merged.values
      end

      private

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

      # Почему на этой стадии любая роль выходит «не выведено».
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
