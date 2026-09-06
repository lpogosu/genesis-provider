# frozen_string_literal: true

module SpecGen
  module Diff
    # Общее поведение сравнения одного раздела IR: наследник объявляет
    # `compare` и складывает найденное через `add`.
    #
    # Все сравнения идут по значениям, а не по обоснованиям: `Derived`
    # сравнивается через `#value`, потому что смена источника при том же
    # значении ничего не меняет ни в сервисе, ни в документации. Описания и
    # примеры не сравниваются вовсе — их правят в каждой второй версии
    # спецификации, и отчёт о сравнении утонул бы в них.
    class Area
      # @param old [IR::ProviderProfile] прежняя версия
      # @param new [IR::ProviderProfile] новая версия
      def initialize(old, new)
        @old = old
        @new = new
        @changes = []
      end

      # @return [Array<Change>] в порядке обнаружения; общий порядок задаёт
      #   Diff.call
      def call
        compare
        @changes
      end

      private

      attr_reader :old, :new

      # @return [void] наследник обязан переопределить
      def compare
        raise NotImplementedError, "#{self.class}#compare"
      end

      def add(kind, json_path:, before: nil, after: nil, impact: nil)
        @changes << Change.build(kind, json_path: json_path, before: before, after: after,
                                       impact: impact)
      end

      # Изменение одного члена: молчит, пока значения равны.
      def changed(kind, before, after, json_path:, impact: nil)
        return if before == after

        add(kind, before: before, after: after, json_path: json_path, impact: impact)
      end

      # @param derived [IR::Derived, nil]
      # @return [Object, nil] значение, если оно выведено
      def value_of(derived)
        derived&.known? ? derived.value : nil
      end

      # Значение члена-Derived у объекта, которого может не быть вовсе:
      # раздела, исчезнувшего целиком, и раздела с невыведенным членом отчёт
      # касается одинаково — значения нет.
      # @param node [#[], nil] объект IR
      # @param member [Symbol] имя члена
      # @return [Object, nil]
      def member_of(node, member)
        node.nil? ? nil : value_of(node[member])
      end

      # Обходит объединение ключей двух наборов в устойчивом порядке и отдаёт
      # пару элементов; отсутствующий с одной стороны приходит как nil.
      # @param before [Hash] прежние элементы по ключу
      # @param after [Hash] новые элементы по ключу
      # @yieldparam key [Object]
      # @yieldparam was [Object, nil]
      # @yieldparam now [Object, nil]
      # @return [void]
      def each_element(before, after)
        (before.keys | after.keys).sort_by(&:to_s).each do |key|
          yield(key, before[key], after[key])
        end
      end

      # Адрес элемента: новый, если он есть, иначе прежний. Исчезнувший
      # элемент нельзя показать адресом в новой спецификации — его там нет.
      def address(was, now)
        (now || was)&.json_path
      end
    end
  end
end
