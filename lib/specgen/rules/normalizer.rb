# frozen_string_literal: true

module SpecGen
  module Rules
    # Сводит имя поля или заголовка к той форме, по которой ключуются
    # справочники: нижний регистр, одиночные подчёркивания между словами.
    # "X-Payer-Phone", "payerPhone" и "payer phone" дают одно и то же
    # "payer_phone", поэтому синоним заводится один раз, а не по разу на
    # каждое написание, и столкновение двух ролей ловится между написаниями,
    # а не только внутри одного.
    module Normalizer
      ACRONYM_BOUNDARY = /([A-Z]+)([A-Z][a-z])/
      CAMEL_BOUNDARY = /([a-z\d])([A-Z])/
      SEPARATOR = /[^a-z0-9]+/
      EDGES = /\A_+|_+\z/

      # @param name [String, Symbol, nil]
      # @return [String] нормализованное имя; пустое, если от имени ничего
      #   не осталось
      def self.call(name)
        name.to_s
            .gsub(ACRONYM_BOUNDARY, '\1_\2')
            .gsub(CAMEL_BOUNDARY, '\1_\2')
            .downcase
            .gsub(SEPARATOR, '_')
            .gsub(EDGES, '')
      end

      # @param name [String, Symbol, nil]
      # @return [Array<String>] слова нормализованного имени
      def self.tokens(name)
        call(name).split('_')
      end
    end
  end
end
