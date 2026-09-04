# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Мост между IR и матчерами полей: как поле схемы и параметр операции
    # становятся Matchers::Subject, как решение матчеров ложится в IR и как
    # его замечания превращаются в Note для анализатора.
    #
    # Поле тела и параметр сопоставляются с ролями одним механизмом — отсюда
    # один модуль на обоих, чтобы SchemaReader и ParameterReader не собирали
    # Subject каждый по-своему. Родителем поля считается имя его схемы: у
    # компонентной схемы это имя компонента (`Recipient`), у инлайновой —
    # синтетическое имя по месту (`Thing.properties.recipient`), и в обоих
    # StructureMatcher находит нужный токен.
    module RoleSubjects
      EXTENSION = Matchers::Remarks::EXTENSION

      # @param field [IR::Field]
      # @param schema_name [String] имя схемы, в которой лежит поле
      # @param node [Hash] свёрнутый узел свойства, ради x-specgen-role
      # @return [Matchers::Subject]
      def self.field(field, schema_name, node)
        Matchers::Subject.new(name: field.name, type: field.type, format: field.format,
                              constraints: field.constraints, example: field.example,
                              parents: [schema_name], required: field.required?,
                              container: field.schema ? true : nil, overlay: node[EXTENSION],
                              json_path: field.json_path)
      end

      # @param parameter [IR::Parameter]
      # @param item [Hash] Parameter Object, ради schema и x-specgen-role
      # @return [Matchers::Subject]
      def self.parameter(parameter, item)
        schema = item['schema'].is_a?(Hash) ? item['schema'] : {}
        Matchers::Subject.new(name: parameter.name, type: parameter.type,
                              format: parameter.format, constraints: ConstraintReader.call(schema),
                              example: parameter.example, location: parameter.location,
                              required: parameter.required?,
                              overlay: item[EXTENSION] || schema[EXTENSION],
                              json_path: parameter.json_path)
      end

      # Проставляет роли и собирает замечания.
      # @param assigner [Matchers::Assigner]
      # @param targets [Array<IR::Field, IR::Parameter>] что получает роль
      # @param subjects [Array<Matchers::Subject>] по одному на target
      # @return [Array<Note>]
      def self.assign(assigner, targets, subjects)
        assigner.call(subjects).zip(targets).flat_map do |outcome, target|
          target.role = outcome.derived
          outcome.remarks.map { |remark| note(remark, target.json_path) }
        end
      end

      # @param remark [Matchers::Remark]
      # @param json_path [String, nil]
      # @return [Note]
      def self.note(remark, json_path)
        Note.new(code: remark.code, message: remark.message, json_path: json_path,
                 severity: remark.severity, suggested_overlay: remark.suggested_overlay)
      end
    end
  end
end
