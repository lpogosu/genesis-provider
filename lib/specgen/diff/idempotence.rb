# frozen_string_literal: true

module SpecGen
  module Diff
    # Идемпотентность: имя заголовка, обязательность и код успешной
    # дедупликации.
    #
    # Обязательность — единственный член раздела, который не меняет сервис:
    # ключ отправляется всегда, даже когда спецификация пометила заголовок
    # необязательным (черновик IETF draft-ietf-httpapi-idempotency-key-header).
    # Меняется таблица методов в INTEGRATION.md, и только она.
    class Idempotence < Area
      # Вид изменения → член IR::Idempotency.
      MEMBERS = { idempotency_header_changed: :header,
                  idempotency_conflict_changed: :conflict_status }.freeze

      private

      def compare
        was = old.idempotency
        now = new.idempotency
        return if was.nil? && now.nil?

        at = address(was, now)
        MEMBERS.each do |kind, member|
          changed(kind, member_of(was, member), member_of(now, member), json_path: at)
        end
        changed(:idempotency_required_changed, required(was), required(now), json_path: at)
      end

      def required(idempotency)
        return nil if idempotency.nil?

        idempotency.required ? :required : :optional
      end
    end
  end
end
