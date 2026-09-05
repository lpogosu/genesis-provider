# frozen_string_literal: true

module SpecGen
  module Generators
    module Service
      # Тела приватных методов, которые не зависят ни от спецификации, ни от
      # справочников: разбор JSON, чистка payload, UUID v5 по RFC 4122 §4.3,
      # чтение заголовка без учёта регистра, константное сравнение подписи.
      #
      # Они лежат данными и отдельно от Privates по двум причинам: их видно
      # целиком одним куском (их читают глазами вместе со сгенерированным
      # файлом), и Privates остаётся про сборку методов, а не про их текст.
      module Snippets
        UUID_V5 = [
          "digest = Digest::SHA1.digest([namespace.delete('-')].pack('H*') + name.to_s)",
          'bytes = digest.bytes[0, 16]',
          'bytes[6] = (bytes[6] & 0x0f) | 0x50', 'bytes[8] = (bytes[8] & 0x3f) | 0x80',
          "hex = bytes.pack('C*').unpack1('H*')",
          "[hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')"
        ].freeze
        PARSE_JSON = ['parsed = JSON.parse(text.to_s)', 'parsed.is_a?(Hash) ? parsed : {}',
                      'rescue JSON::ParserError', '{}'].freeze
        COMPACT = ['return value unless value.is_a?(Hash)', '',
                   'value.transform_values { |item| compact_payload(item) }.compact'].freeze
        HEADER_VALUE = ['return nil if name.nil? || headers.nil?', '',
                        'headers.find { |key, _value| key.to_s.casecmp?(name) }&.last'].freeze
        SECURE_EQUAL = ['return false unless expected.to_s.bytesize == given.to_s.bytesize', '',
                        'OpenSSL.fixed_length_secure_compare(expected.to_s, given.to_s)'].freeze
        MATCHES = ['given.split.any? do |item|',
                   '  secure_equal?(expected, item.delete_prefix(SIGNATURE_VALUE_PREFIX))',
                   'end'].freeze
        # Код отказа для платформы: по HTTP-коду ответа, иначе по действию из
        # ERROR_MAP. Обе таблицы — данные из rules/contract.yml.
        PLATFORM_FAILURE_CODE = ['FAILURE_CODES[status] || FAILURE_CODES_BY_ACTION[action]'].freeze
        # Методы с постоянным телом: имя → параметры и строки.
        FIXED = {
          map_status: [['raw'], ['STATUS_MAP[raw.to_s]']],
          parse_json: [['text'], PARSE_JSON],
          compact_payload: [['value'], COMPACT],
          uuid_v5: [%w[namespace name], UUID_V5],
          header_value: [%w[headers name], HEADER_VALUE],
          secure_equal?: [%w[expected given], SECURE_EQUAL],
          platform_failure_code: [%w[status action], PLATFORM_FAILURE_CODE]
        }.freeze
      end
    end
  end
end
