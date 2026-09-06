# frozen_string_literal: true

module SpecGen
  module Generators
    # Имена сгенерированных сущностей из имени провайдера: файл в snake_case
    # (`acme_pay_service.rb`), класс в CamelCase (`AcmePayService`),
    # переменная окружения (`ACME_PAY_BASE_URL`).
    #
    # Вход — slug из IR::Info#name, который InfoAnalyzer уже собрал из
    # --provider или info.title. Здесь он ещё раз приводится к безопасному
    # идентификатору: чужие спецификации называются как угодно («ЮKassa
    # API», «Adyen Payout API»), а результат обязан быть валидной константой
    # Ruby и именем файла на любой файловой системе. Преобразование
    # детерминировано: одна строка — одно имя.
    class Naming
      FALLBACK = 'provider'
      SUFFIX = 'service'
      OVERLAY_SUFFIX = 'overlay.yaml'
      # Кириллица → латиница, чтобы русское имя провайдера не исчезало из
      # идентификатора целиком. Транслитерация упрощённая, без ё/й-нюансов:
      # цель — читаемый ASCII, а не стандарт ГОСТ.
      CYRILLIC = {
        'а' => 'a', 'б' => 'b', 'в' => 'v', 'г' => 'g', 'д' => 'd', 'е' => 'e', 'ё' => 'yo',
        'ж' => 'zh', 'з' => 'z', 'и' => 'i', 'й' => 'y', 'к' => 'k', 'л' => 'l', 'м' => 'm',
        'н' => 'n', 'о' => 'o', 'п' => 'p', 'р' => 'r', 'с' => 's', 'т' => 't', 'у' => 'u',
        'ф' => 'f', 'х' => 'kh', 'ц' => 'ts', 'ч' => 'ch', 'ш' => 'sh', 'щ' => 'sch', 'ъ' => '',
        'ы' => 'y', 'ь' => '', 'э' => 'e', 'ю' => 'yu', 'я' => 'ya'
      }.freeze
      NON_SLUG = /[^a-z0-9]+/
      COMBINING = /\p{Mn}/
      # Идентификатор класса не может начинаться с цифры.
      DIGIT_PREFIX = 'p'

      # @return [String] snake_case-имя провайдера, например "acme_pay"
      attr_reader :slug

      # @param profile [IR::ProviderProfile]
      # @return [Naming] имена по IR::Info#name; без имени — по FALLBACK
      def self.for(profile)
        new(profile.info&.name&.value)
      end

      # @param raw [String, nil] имя провайдера в любом виде
      def initialize(raw)
        @slug = slugify(raw)
        freeze
      end

      # @return [String] "acme_pay_service.rb"
      def file_name
        "#{slug}_#{SUFFIX}.rb"
      end

      # @return [String] "acme_pay.overlay.yaml" — заготовка переопределений;
      #   имя обещано читателю разделом «Как собрать overlay» в report.md,
      #   поэтому оно одно для отчёта и для флага --fix
      def overlay_file_name
        "#{slug}.#{OVERLAY_SUFFIX}"
      end

      # @return [String] "AcmePayService"
      def class_name
        "#{camel(slug)}#{camel(SUFFIX)}"
      end

      # @return [String] "ACME_PAY_BASE_URL"
      def env_name
        env('BASE_URL')
      end

      # @param suffix [String] "OPEN_TIMEOUT", "READ_TIMEOUT"
      # @return [String] "ACME_PAY_OPEN_TIMEOUT" — переменная окружения с
      #   префиксом провайдера; одно правило для всех артефактов
      def env(suffix)
        "#{slug.upcase}_#{suffix}"
      end

      private

      # @return [String] непустой slug из [a-z0-9_], не начинающийся с цифры
      def slugify(raw)
        text = raw.to_s.unicode_normalize(:nfkd).gsub(COMBINING, '').downcase
        text = text.gsub(/[а-яё]/) { |letter| CYRILLIC.fetch(letter) }
        words = text.split(NON_SLUG).reject(&:empty?)
        return FALLBACK if words.empty?

        slug = words.join('_')
        slug.match?(/\A\d/) ? "#{DIGIT_PREFIX}#{slug}" : slug
      end

      def camel(text)
        text.split('_').map(&:capitalize).join
      end
    end
  end
end
