# frozen_string_literal: true

module SpecGen
  module Matchers
    # Что матчеры знают об одном поле или параметре — нейтрально к тому,
    # откуда оно взялось. Поле тела и параметр операции сопоставляются с
    # ролями одним механизмом, поэтому оба сначала сводятся к Subject.
    #
    #   name         имя дословно
    #   type         тип JSON Schema дословно или nil
    #   format       format дословно или nil
    #   constraints  Hash с ключами IR::Field::CONSTRAINT_KEYS
    #   example      значение example или nil
    #   parents      имена родителей: свойство, под которым лежит объект,
    #                и/или имя схемы; сравниваются по токенам
    #   location     :body у поля тела, иначе одно из IR::Parameter::LOCATIONS
    #   required     обязательно ли поле или параметр
    #   container    поле — объект или массив, роли получают его вложенные
    #                поля, а не оно само
    #   overlay      значение расширения x-specgen-role или nil
    #   json_path    JSONPath поля — цель для фрагмента overlay
    Subject = Struct.new(:name, :type, :format, :constraints, :example, :parents, :location,
                         :required, :container, :overlay, :json_path, keyword_init: true)

    # Значения по умолчанию и выборки Subject.
    class Subject
      BODY = :body
      CONTAINERS = %w[object array].freeze

      # @param name [String]
      # @param type [String, nil]
      # @param format [String, nil]
      # @param constraints [Hash{Symbol => Object}]
      # @param example [Object, nil]
      # @param parents [Array<String>]
      # @param location [Symbol]
      # @param required [Boolean]
      # @param container [Boolean, nil] nil — определить по типу
      # @param overlay [Object, nil]
      # @param json_path [String, nil]
      def initialize(name:, type: nil, format: nil, constraints: {}, example: nil, parents: [],
                     location: BODY, required: false, container: nil, overlay: nil,
                     json_path: nil)
        super
        self.container = CONTAINERS.include?(type) if container.nil?
        freeze
      end

      # @return [String] имя, нормализованное как в справочниках
      def normalized
        Rules::Normalizer.call(name)
      end

      # @return [Array<String>] токены имени
      def tokens
        Rules::Normalizer.tokens(name)
      end

      # @return [Boolean] параметр операции, а не поле тела
      def parameter?
        location != BODY
      end

      # @return [Boolean]
      def required?
        required == true
      end
    end
  end
end
