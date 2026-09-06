# frozen_string_literal: true

module SpecGen
  module Diff
    # Авторизация: тип, место, имя параметра, ключи `provider.credentials`.
    #
    # Профиль без авторизации (`auth` равен nil) сравнивается членами: смена
    # схемы на «никакой» читается как «было X-API-Key, стало ничего», а не как
    # отдельный вид изменения — для сгенерированного сервиса это одно и то же
    # решение.
    class Authorization < Area
      private

      def compare
        was = old.auth
        now = new.auth
        return if was.nil? && now.nil?

        compare_scheme(was, now, address(was, now))
        compare_place(was, now, address(was, now))
      end

      def compare_scheme(was, now, at)
        changed(:auth_type_changed, member_of(was, :type), member_of(now, :type), json_path: at)
        changed(:auth_credentials_changed, keys(was), keys(now), json_path: at)
      end

      # Место и имя параметра — не Derived: их спецификация называет прямо
      # или не называет вовсе.
      def compare_place(was, now, at)
        changed(:auth_location_changed, was&.location, now&.location, json_path: at)
        changed(:auth_param_changed, was&.param_name, now&.param_name, json_path: at)
      end

      def keys(auth)
        value = member_of(auth, :credential_keys)
        value.nil? ? nil : Array(value)
      end
    end
  end
end
