# frozen_string_literal: true

module SpecGen
  module Generators
    # UUID версии 5 (RFC 4122 §4.3): SHA-1 от пространства имён и имени,
    # версия 5, вариант RFC. Ровно тот же алгоритм печатает шаблон сервиса
    # приватным методом uuid_v5, поэтому ключ идемпотентности в fixtures.json
    # совпадает с тем, который сервис посчитает для той же операции.
    #
    # Никакого SecureRandom: ключ обязан быть детерминированным, иначе повтор
    # запроса не дедуплицируется.
    module Uuid
      module_function

      # @param namespace [String] UUID пространства имён с дефисами или без
      # @param name [String] имя внутри пространства
      # @return [String] UUID v5 в каноническом виде
      def v5(namespace, name)
        digest = Digest::SHA1.digest([namespace.to_s.delete('-')].pack('H*') + name.to_s)
        canonical(stamp(digest.bytes[0, 16]))
      end

      # @param bytes [Array<Integer>] первые 16 байт SHA-1
      # @return [Array<Integer>] с версией 5 и вариантом RFC 4122
      def stamp(bytes)
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        bytes
      end

      # @param bytes [Array<Integer>]
      # @return [String] 8-4-4-4-12
      def canonical(bytes)
        hex = bytes.pack('C*').unpack1('H*')
        [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
      end
    end
  end
end
