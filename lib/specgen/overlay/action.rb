# frozen_string_literal: true

module SpecGen
  module Overlay
    # Одно действие overlay: цель и то, что с ней сделать — слить объект
    # (`update`) или удалить узел (`remove`).
    #
    # Спецификация Overlay 1.0.0 говорит, что `update` не имеет действия при
    # `remove: true`. Мы такое действие отвергаем, а не выполняем половину:
    # человек, написавший оба ключа, не знает, о чём просит, а молча
    # выполненная половина overlay — ровно тот отказ, от которого эта стадия
    # защищает.
    class Action
      TARGET = 'target'
      UPDATE = 'update'
      REMOVE = 'remove'
      DESCRIPTION = 'description'

      # @return [Target]
      attr_reader :target
      # @return [Hash, nil] объект для слияния
      attr_reader :update
      # @return [String, nil] пояснение действия из самого overlay
      attr_reader :description
      # @return [String] место действия внутри файла overlay
      attr_reader :json_path

      # @param node [Object] элемент массива `actions`
      # @param file [String] файл overlay, для сообщений
      # @param index [Integer] номер действия в массиве
      # @return [Action]
      # @raise [OverlayError]
      def self.parse(node, file:, index:)
        new(node, file: file, json_path: SpecLoader::JsonPath.build([Document::ACTIONS, index]))
      end

      # @param node [Object]
      # @param file [String]
      # @param json_path [String]
      def initialize(node, file:, json_path:)
        @file = file
        @json_path = json_path
        check_object(node)
        @target = target_of(node)
        @remove = remove_of(node)
        @update = update_of(node)
        @description = node[DESCRIPTION].is_a?(String) ? node[DESCRIPTION] : nil
        check_intent
        freeze
      end

      # @return [Boolean]
      def remove?
        @remove
      end

      # @return [Symbol] :update или :remove
      def kind
        remove? ? :remove : :update
      end

      private

      def check_object(node)
        return if node.is_a?(Hash)

        fail!('action_type', type: SpecLoader::TypeName.of(node))
      end

      def target_of(node)
        value = node[TARGET]
        fail!('target_absent') if value.nil?
        fail!('target_type', type: SpecLoader::TypeName.of(value)) unless value.is_a?(String)

        Target.parse(value) || fail!('target_syntax', target: value.inspect)
      end

      def remove_of(node)
        value = node[REMOVE]
        return false if value.nil?

        fail!('remove_type', value: value.inspect) unless [true, false].include?(value)

        value
      end

      def update_of(node)
        value = node[UPDATE]
        return nil if value.nil?

        fail!('update_type', type: SpecLoader::TypeName.of(value)) unless value.is_a?(Hash)

        value
      end

      # Действие обязано просить ровно одно, а удалить корень документа
      # нельзя: у него нет контейнера, из которого его удаляют.
      def check_intent
        fail!('action_both') if remove? && !update.nil?
        fail!('action_empty') if !remove? && update.nil?
        fail!('remove_root') if remove? && target.root?
      end

      def fail!(key, **params)
        Overlay.fail!(key, file: @file, path: @json_path, **params)
      end
    end
  end
end
