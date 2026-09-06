# frozen_string_literal: true

module SpecGen
  module Diff
    # Операции: появилась, исчезла, сменила роль, сменила метод или путь.
    #
    # Операции связываются по `Operation#key` — operationId, а если его нет, то
    # `post_payouts`. Это тот же ключ, которым на операцию ссылаются правила
    # ошибок и идемпотентность, поэтому переименование `operationId` честно
    # читается как «одна исчезла, другая появилась»: для всего остального
    # конвейера это и правда другая операция.
    class Operations < Area
      private

      def compare
        each_element(index(old), index(new)) do |key, was, now|
          next add(:operation_added, json_path: now.json_path, after: key) if was.nil?
          next add(:operation_removed, json_path: was.json_path, before: key) if now.nil?

          compare_operation(was, now)
        end
      end

      def index(profile)
        profile.operations.to_h { |operation| [operation.key, operation] }
      end

      def compare_operation(was, now)
        changed(:operation_role_changed, value_of(was.role), value_of(now.role),
                json_path: now.json_path)
        changed(:operation_endpoint_changed, endpoint(was), endpoint(now),
                json_path: now.json_path)
      end

      def endpoint(operation)
        "#{operation.http_method.to_s.upcase} #{operation.path}"
      end
    end
  end
end
