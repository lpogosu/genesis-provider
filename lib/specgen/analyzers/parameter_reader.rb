# frozen_string_literal: true

module SpecGen
  module Analyzers
    # The parameters of one operation, including the ones it inherits.
    #
    # OpenAPI declares parameters in two places: on the path item, where
    # every operation of that path inherits them, and on the operation
    # itself, which overrides an inherited one with the same name and
    # location. Missing that inheritance loses the path identifier of every
    # `GET /payouts/{id}` written the tidy way, so it is modelled here
    # rather than left to each caller.
    #
    # Roles are deliberately not matched here. A parameter carries a role
    # like a field does, but matching names to roles is the field matchers'
    # job, and inventing a role in two places would make them disagree.
    class ParameterReader
      # Why every role comes out unknown at this stage.
      ROLE_PENDING = 'parameter roles are matched by the field matchers, a later stage'

      # @return [Array<Array(String, String)>] message and JSONPath of every
      #   parameter the caller should warn about
      attr_reader :problems

      # @param shared [Object] `parameters` of the path item
      # @param own [Object] `parameters` of the operation
      # @param shared_path [String] JSONPath of the path item's list
      # @param own_path [String] JSONPath of the operation's list
      def initialize(shared:, own:, shared_path:, own_path:)
        @shared = shared
        @own = own
        @shared_path = shared_path
        @own_path = own_path
        @problems = []
      end

      # Inherited parameters keep their place; an override replaces the
      # inherited entry in it, and a parameter only the operation declares
      # is appended.
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
          problem('`parameters` must be a list', at)
          return []
        end

        list.each_with_index.filter_map { |item, index| parameter(item, "#{at}[#{index}]") }
      end

      def parameter(item, at)
        return problem('parameter must be an object', at) unless item.is_a?(Hash)

        name = item['name']
        location = location_of(item['in'])
        return problem('parameter needs a `name` and a known `in`', at) if bad?(name, location)

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

      def pending_role
        IR::Derived.unknown(evidence: ROLE_PENDING)
      end

      # @return [nil] so a filter_map drops the parameter it describes
      def problem(message, at)
        @problems << [message, at]
        nil
      end
    end
  end
end
