# frozen_string_literal: true

module SpecGen
  module Generators
    module Integration
      # Раздел 7: схема подписи вебхука. Значения — из Service::Signature,
      # те же, что стали константами SIGNATURE_* сервиса; невыведенный
      # параметр показан со значением по умолчанию и пометкой. Без профиля
      # раздел говорит, что сервис отклоняет все уведомления, и даёт
      # overlay-фрагмент из предупреждения анализатора.
      class SignatureDoc < Base
        MEMBERS = %i[header algorithm encoding payload secret_key].freeze

        # @return [Symbol] :none (вебхуков нет), :absent (подпись не
        #   выведена), :ok
        def state
          return :none if ctx.webhook.nil?
          return :absent if signature.profile.nil? || !signature.known?(:header)

          :ok
        end

        # @return [String] абзац для состояний :none и :absent
        def note
          case state
          when :none
            t('sig_none_webhook', method: code(contract.method_for(:webhook)&.name.to_s),
                                  failure: failure(Service::Callback::MISSING_CODE))
          when :absent then t('sig_absent', failure: failure(:signature_missing), report: report)
          end
        end

        # @return [Array<Array<String>>] параметр, значение, источник
        def rows
          rows = MEMBERS.map { |member| member_row(member) }
          rows << member_row(:tolerance) if signature.timestamped?
          prefix = signature.value_prefix
          rows << [t('sig_prefix_col'), code(prefix), t('sig_prefix_source')] if prefix
          rows
        end

        # @return [Array<String>] правила проверки словами
        def rules_lines
          lines = [t('sig_missing_header', failure: failure(:signature_missing)),
                   t('sig_invalid', failure: failure(:signature_invalid)), t('sig_compare')]
          if signature.timestamped?
            lines << t('sig_replay', tolerance: signature.value(:tolerance),
                                     failure: failure(:signature_expired))
          end
          prefix = signature.value_prefix
          lines << t('sig_prefix_rule', prefix: code(prefix)) if prefix
          lines
        end

        # @return [Array<String>] пример вычисления подписи на Ruby, без секрета
        def example_lines
          data = signature.timestamped? ? 'signed' : 'raw_body'
          lines = ["secret = provider.credentials[:#{signature.value(:secret_key)}]"]
          lines << "signed = [#{code_headers}, raw_body].join('.')" if signature.timestamped?
          lines << "expected = #{digest_expression(data)}"
          lines << "given = headers['#{signature.value(:header)}']#{strip_prefix}"
          lines << 'valid = OpenSSL.fixed_length_secure_compare(expected, given)'
          lines
        end

        # @return [String, nil] overlay-фрагмент x-specgen-signature из
        #   предупреждения анализатора; nil, если его нет
        def overlay
          warning = profile.sorted_warnings.find do |w|
            w.fixable? && w.suggested_overlay.include?('x-specgen-signature')
          end
          warning&.suggested_overlay
        end

        private

        def signature
          parts[:signature]
        end

        def member_row(member)
          value = signature.value(member)
          shown = member == :secret_key ? "provider.credentials[:#{value}]" : value.to_s
          [t("sig_member_#{member}"), code(shown), source(member)]
        end

        def source(member)
          return label(signature.profile.public_send(member)) if signature.known?(member)

          evidence = signature.profile&.public_send(member)&.evidence || t('sig_no_profile')
          t('sig_member_source_default', evidence: evidence)
        end

        def code_headers
          [signature.profile.id_header, signature.profile.timestamp_header]
            .map { |header| "headers['#{header}']" }.join(', ')
        end

        def digest_expression(data)
          algorithm = Service::Signature::DIGESTS.fetch(signature.value(:algorithm))
          hex = signature.value(:encoding) == :hex
          return "OpenSSL::HMAC.hexdigest('#{algorithm}', secret, #{data})" if hex

          "[OpenSSL::HMAC.digest('#{algorithm}', secret, #{data})].pack('m0')"
        end

        def strip_prefix
          prefix = signature.value_prefix
          prefix ? ".split.map { |v| v.delete_prefix('#{prefix}') }" : ''
        end
      end
    end
  end
end
