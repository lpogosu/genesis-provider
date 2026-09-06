# frozen_string_literal: true

module SpecGen
  module Diff
    # Карта статусов: статус появился, исчез или сменил внутренний статус.
    #
    # Адрес статуса — запись enum (`...status.enum[2]`), и по индексу нельзя
    # понять, о каком статусе речь, поэтому имя ведёт значение: «completed =
    # approved». Переименование статуса читается как пара «исчез — появился»:
    # STATUS_MAP сгенерированного сервиса ключуется именем, и другого имени
    # он не узнает.
    class Statuses < Area
      private

      def compare
        each_element(index(old), index(new)) do |_name, was, now|
          next add(:status_added, json_path: now.json_path, after: text(now)) if was.nil?
          next add(:status_removed, json_path: was.json_path, before: text(was)) if now.nil?

          changed(:status_internal_changed, text(was), text(now), json_path: now.json_path)
        end
      end

      def index(profile)
        profile.status_map.to_h { |mapping| [mapping.provider_status, mapping] }
      end

      def text(mapping)
        Change.pair(mapping.provider_status, value_of(mapping.internal))
      end
    end
  end
end
