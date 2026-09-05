# frozen_string_literal: true

module SpecGen
  module Overlay
    # Что сделала стадия: какие действия применились, что при этом было
    # переопределено и какие цели не нашлись.
    #
    # Предупреждения пишет сама стадия, а не анализатор. Причина —
    # происхождение: только applier знает, что стояло в спецификации до
    # слияния. Анализатор видит уже единый документ и честно назвал бы
    # переопределённое значение структурным, то есть тем, что написал
    # провайдер. Поэтому `overlay_conflict` рождается здесь, а
    # `Analyzers::Runner` только переносит готовые предупреждения в профиль.
    class Result
      # Длина, после которой значение в тексте предупреждения сокращается:
      # переопределить можно и целую схему, а предупреждение — одна строка.
      BRIEF = 60

      # Одно переопределение: место, значение спецификации и значение
      # overlay. У удаления значения overlay нет — узла больше нет вовсе.
      Change = Struct.new(:json_path, :before, :after, :removed, keyword_init: true) do
        # @return [Boolean] узел удалён, а не заменён
        def removed?
          removed ? true : false
        end

        # @return [String] значение спецификации, сокращённое до строки
        def before_text
          Result.brief(before)
        end

        # @return [String] значение overlay, сокращённое до строки
        def after_text
          Result.brief(after)
        end
      end

      # Одно выполненное действие — то, что печатает отчёт и CLI.
      Applied = Struct.new(:target, :kind, :description, keyword_init: true)

      # @return [String] путь файла overlay
      attr_reader :file
      # @return [String] заголовок overlay
      attr_reader :title
      # @return [Array<Applied>] в порядке файла
      attr_reader :applied
      # @return [Array<Change>] в порядке применения
      attr_reader :conflicts
      # @return [Array<String>] цели, не найденные в спецификации
      attr_reader :misses

      # @param value [Object]
      # @return [String] `inspect`, сокращённый до BRIEF символов
      def self.brief(value)
        text = value.inspect
        text.length <= BRIEF ? text : "#{text[0, BRIEF - 1]}…"
      end

      # @param file [String]
      # @param title [String]
      # @param applied [Array<Applied>]
      # @param conflicts [Array<Change>]
      # @param misses [Array<String>]
      def initialize(file:, title:, applied:, conflicts:, misses:)
        @file = file
        @title = title
        @applied = applied.freeze
        @conflicts = conflicts.freeze
        @misses = misses.freeze
        freeze
      end

      # Переносит найденное в профиль: сам лог и предупреждения. Ненайденная
      # цель — предупреждение, а не ошибка: генерацию не блокирует ничто, а
      # overlay, написанный под прошлую версию спецификации, обязан
      # оставаться применимым в той части, которая ещё адресуется.
      # @param profile [IR::ProviderProfile]
      # @return [Result] себя
      def warn_into(profile)
        profile.overlay = self
        misses.each do |target|
          profile.warn(:overlay_target_missing,
                       Texts.t('overlay.target_missing', target: target, file: file),
                       json_path: target)
        end
        conflicts.each { |change| conflict(profile, change) }
        self
      end

      # Простые данные для дампа профиля: значения «было» и «стало» уже
      # сокращены до строк, поэтому в `ProviderProfile#to_h` не попадает ни
      # одного объекта, который нельзя сериализовать.
      # @return [Hash{Symbol => Object}]
      def to_h
        { file: file, title: title, applied: applied.map(&:to_h),
          conflicts: conflicts.map { |change| change_to_h(change) }, misses: misses }
      end

      # @return [Boolean] overlay не изменил ничего
      def empty?
        applied.empty?
      end

      private

      def change_to_h(change)
        { json_path: change.json_path, before: change.before_text,
          after: change.removed? ? nil : change.after_text, removed: change.removed? }
      end

      def conflict(profile, change)
        key = change.removed? ? 'removed' : 'conflict'
        profile.warn(:overlay_conflict,
                     Texts.t("overlay.#{key}", file: file, before: change.before_text,
                                               after: change.after_text),
                     json_path: change.json_path)
      end
    end
  end
end
