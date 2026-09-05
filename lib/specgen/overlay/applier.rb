# frozen_string_literal: true

module SpecGen
  module Overlay
    # Применяет действия overlay к исходному документу спецификации по
    # порядку файла.
    #
    # Три исхода у действия, и каждый виден. Действие применилось — строка в
    # Result#applied, её печатает CLI и отчёт. Действие переопределило то,
    # что спецификация говорила иначе, — Result#conflicts, из которого
    # рождается `overlay_conflict`: overlay побеждает всегда, но молча не
    # побеждает никогда. Цель не нашлась — Result#misses и
    # `overlay_target_missing`: остальные действия применяются, потому что
    # генерацию не блокирует ничто, а overlay под прошлую версию
    # спецификации обычно верен в остальной части.
    class Applier
      # @param overlay [Document] разобранный файл overlay
      def initialize(overlay)
        @overlay = overlay
        @applied = []
        @conflicts = []
        @misses = []
      end

      # @param data [Hash] исходный документ спецификации; меняется на месте
      # @return [Result]
      # @raise [OverlayError] действие невыполнимо по существу
      def call(data)
        @overlay.actions.each { |action| apply(action, data) }
        Result.new(file: @overlay.file, title: @overlay.title, applied: @applied,
                   conflicts: @conflicts, misses: @misses)
      end

      private

      def apply(action, data)
        node = action.target.resolve(data)
        return @misses << action.target.to_s if Target::MISSING.equal?(node)

        action.remove? ? remove(action, data) : update(action, node)
        @applied << Result::Applied.new(target: action.target.to_s, kind: action.kind,
                                        description: action.description)
      end

      # `remove` удаляет узел из того, что его содержит (Overlay 1.0.0,
      # Action Object). Удаление элемента массива сдвигает индексы, поэтому
      # действия, адресующие соседей по индексу, пишутся до него.
      def remove(action, data)
        parent, key = action.target.container(data)
        removed = parent.is_a?(Array) ? parent.delete_at(key) : parent.delete(key.to_s)
        @conflicts << Result::Change.new(json_path: action.target.to_s, before: removed,
                                         removed: true)
      end

      # Цель-объект сливается, цель-массив получает `update` последним
      # элементом (то же описание Action Object). Цель-скаляр слить не с
      # чем: это не расхождение версий, а неверная инструкция, поэтому
      # ошибка стадии, а не предупреждение.
      def update(action, node)
        return node << action.update if node.is_a?(Array)

        unless node.is_a?(Hash)
          Overlay.fail!('update_target_type', file: @overlay.file, path: action.target.to_s,
                                              type: SpecLoader::TypeName.of(node))
        end

        Merge.new(@conflicts).call(node, action.update, action.target.keys)
      end
    end
  end
end
