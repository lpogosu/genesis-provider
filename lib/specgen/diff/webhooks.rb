# frozen_string_literal: true

module SpecGen
  module Diff
    # Вебхуки: точка приёма, события и профиль подписи.
    #
    # Профиль подписи сравнивается по членам, которые решают, как выглядит
    # `verify_signature!`: заголовок, алгоритм, кодирование и подписываемое
    # тело. Допуск на повтор и ключ секрета сюда не входят намеренно —
    # первый значим только у Standard Webhooks, второй приходит не из
    # спецификации, а из справочника.
    class Webhooks < Area
      # Вид изменения → член IR::SignatureProfile.
      SIGNATURE = { signature_profile_changed: :profile, signature_header_changed: :header,
                    signature_algorithm_changed: :algorithm, signature_encoding_changed: :encoding,
                    signature_payload_changed: :payload }.freeze

      private

      def compare
        each_element(index(old), index(new)) do |path, was, now|
          next add(:webhook_added, json_path: now.json_path, after: path) if was.nil?
          next add(:webhook_removed, json_path: was.json_path, before: path) if now.nil?

          compare_events(was, now)
          compare_signature(was, now)
        end
      end

      def index(profile)
        profile.webhooks.to_h { |webhook| [webhook.path, webhook] }
      end

      def compare_events(was, now)
        each_element(events(was), events(now)) do |_name, before, after|
          if before.nil?
            add(:event_added, json_path: after.json_path, after: event_text(after))
          elsif after.nil?
            add(:event_removed, json_path: before.json_path, before: event_text(before))
          else
            changed(:event_status_changed, event_text(before), event_text(after),
                    json_path: after.json_path)
          end
        end
      end

      def events(webhook)
        webhook.events.to_h { |event| [event.name, event] }
      end

      def event_text(event)
        Change.pair(event.name, value_of(event.internal_status))
      end

      def compare_signature(was, now)
        before = was.signature
        after = now.signature
        return if before.nil? && after.nil?
        return signature_gone(was, before) if after.nil?
        return signature_new(now, after) if before.nil?

        at = after.json_path || now.json_path
        SIGNATURE.each do |kind, member|
          changed(kind, value_of(before[member]), value_of(after[member]), json_path: at)
        end
      end

      def signature_new(webhook, profile)
        add(:signature_added, json_path: profile.json_path || webhook.json_path,
                              after: value_of(profile.header))
      end

      def signature_gone(webhook, profile)
        add(:signature_removed, json_path: profile.json_path || webhook.json_path,
                                before: value_of(profile.header))
      end
    end
  end
end
