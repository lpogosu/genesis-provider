# frozen_string_literal: true

module SpecGen
  module Diff
    # Коды ошибок и действия по ним: правило появилось, исчезло, сменило
    # действие или сменило место, в котором код объявлен.
    #
    # Правило связывается с правилом по своему селектору — операция, HTTP-код
    # и код провайдера, — потому что один и тот же код значит разное у разных
    # операций: 409 при создании это дедупликация, 409 при отмене — отказ.
    class ErrorMap < Area
      private

      def compare
        each_element(index(old), index(new)) do |_key, was, now|
          next add(:error_added, json_path: now.json_path, after: action(now)) if was.nil?
          next add(:error_removed, json_path: was.json_path, before: action(was)) if now.nil?

          compare_rule(was, now)
        end
      end

      def compare_rule(was, now)
        at = now.json_path
        changed(:error_action_changed, action(was), action(now), json_path: at)
        changed(:error_declaration_changed, seen(was), seen(now), json_path: at)
      end

      def index(profile)
        profile.error_map.to_h do |rule|
          [[rule.operation, rule.http_status, rule.provider_code], rule]
        end
      end

      def selector(rule)
        [rule.operation, rule.http_status, rule.provider_code].compact.join(' ')
      end

      def action(rule)
        Change.pair(selector(rule), value_of(rule.action))
      end

      def seen(rule)
        Change.pair(selector(rule), rule.seen_in.map(&:to_s).sort.join('+'))
      end
    end
  end
end
