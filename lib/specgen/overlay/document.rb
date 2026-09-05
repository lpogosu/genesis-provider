# frozen_string_literal: true

module SpecGen
  module Overlay
    # Разобранный файл OpenAPI Overlay 1.0.0: версия формата, заголовок и
    # действия в порядке файла.
    #
    # Почему битый формат — ошибка, а не предупреждение. Overlay человек
    # пишет руками и указывает флагом руками: если файл нельзя прочитать как
    # overlay, у нас нет ни одного действия, о котором он просил, и прогон
    # «как будто переопределений не было» соврал бы молча. Ненайденная цель —
    # другой случай: намерение известно, разошлась спецификация, и это
    # предупреждение профиля (Applier), потому что генерацию не блокирует
    # ничто.
    #
    # Строгость по существу, а не по букве: `info` спецификация требует, но
    # его отсутствие ничего не меняет в результате, поэтому заголовок при
    # отсутствии берётся из имени файла. Проверяется то, без чего действие
    # нельзя выполнить или нельзя понять.
    class Document
      VERSION = 'overlay'
      ACTIONS = 'actions'
      INFO = 'info'
      TITLE = 'title'
      # Поддерживаемая версия формата: 1.0 с любым патчем.
      SUPPORTED = /\A1\.0(\.\d+)?\z/

      # @return [String] путь файла overlay
      attr_reader :file
      # @return [String] заголовок из `info.title` либо имя файла
      attr_reader :title
      # @return [String] значение ключа `overlay`
      attr_reader :version
      # @return [Array<Action>] в порядке файла
      attr_reader :actions

      # @param file [String] путь файла overlay
      # @return [Document]
      # @raise [OverlayError] файла нет, битый синтаксис, это не overlay
      def self.read(file)
        new(file: file, data: SpecLoader::Reader.read(file))
      rescue SpecLoadError => e
        # Reader сообщает про файл и место одинаково для любого YAML или
        # JSON; наружу это обязана быть ошибка своей стадии.
        raise OverlayError.new(e.detail, file: e.file, path: e.path)
      end

      # @param file [String]
      # @param data [Hash] разобранный файл overlay
      def initialize(file:, data:)
        @file = file
        @version = version_of(data)
        @title = title_of(data)
        @actions = actions_of(data).freeze
        freeze
      end

      private

      def version_of(data)
        value = data[VERSION]
        fail!('not_overlay', '$', keys: data.keys.first(5).join(', ')) if value.nil?

        text = value.to_s
        fail!('version_unsupported', "$.#{VERSION}", version: text.inspect) unless
          text.match?(SUPPORTED)

        text
      end

      def title_of(data)
        info = data[INFO]
        title = info.is_a?(Hash) ? info[TITLE] : nil
        title.is_a?(String) && !title.strip.empty? ? title : File.basename(@file)
      end

      def actions_of(data)
        listed = data[ACTIONS]
        fail!('actions_absent', '$') if listed.nil?
        fail!('actions_type', "$.#{ACTIONS}", type: SpecLoader::TypeName.of(listed)) unless
          listed.is_a?(Array)
        fail!('actions_empty', "$.#{ACTIONS}") if listed.empty?

        listed.each_with_index.map { |node, index| Action.parse(node, file: @file, index: index) }
      end

      def fail!(key, path, **params)
        Overlay.fail!(key, file: @file, path: path, **params)
      end
    end
  end
end
