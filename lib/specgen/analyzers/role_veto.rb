# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Отсечки формы: может ли операция вообще играть роль, за которую
    # проголосовали её признаки.
    #
    # Голоса отвечают на вопрос «на что это похоже», отсечка — на вопрос
    # «может ли это быть тем». Пока отсечек не было, `customer_create`
    # получал роль создания выплаты (глагол `create` плюс POST с телом),
    # `product_delete` — отмены, а `GET /transfers` — опроса статуса, потому
    # что имя ресурса в пути тянуло роль ровно на порог. Ложная роль хуже
    # отсутствия роли: она молча затаскивает посторонний ресурс
    # спецификации в контракт и в знаменатель покрытия, а :unmapped виден в
    # отчёте и получает отдельный публичный метод.
    #
    # Все три правила — данные секции `vetoes` в rules/operations.yml.
    class RoleVeto
      # @param book [Rules::OperationsBook]
      # @param tokens [Array<String>] слова пути и operationId
      # @param http_method [Symbol]
      # @param list [Boolean] успешный ответ операции — список (READ_MULTI)
      def initialize(book:, tokens:, http_method:, list:)
        @book = book
        @tokens = tokens
        @http_method = http_method
        @list = list
      end

      # Отсечка касается только роли, которую спецификация вообще назвала:
      # отчёт не должен перечислять отклонённой роль, за которую голосовали
      # лишь HTTP-метод и наличие тела, — о ней нечего отклонять.
      # @param votes [Hash{Symbol => Hash}] голоса опознанных ролей
      # @return [Hash{Symbol => Symbol}] роль => причина отсечки
      def reasons(votes)
        votes.filter_map do |role, vote|
          next if vote.values.sum.zero?

          reason = reason_for(role)
          [role, reason] unless reason.nil?
        end.to_h
      end

      # @param role [Symbol]
      # @return [Symbol, nil] :off_domain, :method_mismatch, :list_response
      def reason_for(role)
        return :off_domain if off_domain?(role)
        return :method_mismatch if method_mismatch?(role)

        :list_response if list?(role)
      end

      private

      attr_reader :book

      # Роль требует, чтобы в имени операции встретилось хотя бы одно её
      # собственное существительное. Отдельного списка слов у отсечки нет
      # намеренно: словарь роли и есть её словарь, а второй список рядом
      # разошёлся бы с ним на первой же правке справочника.
      def off_domain?(role)
        return false unless book.veto(:domain_nouns)[:roles].include?(role)

        !@tokens.intersect?(nouns_of(role))
      end

      # @return [Array<String>] существительные роли: свои, ресурсов и хвоста
      #   пути; глаголы сюда не входят — отсечка требует именно предмета
      def nouns_of(role)
        entry = book.entry(role)
        entry[:nouns] + entry[:resources] + entry[:tail]
      end

      # HTTP-метод уже голосовал; отсечкой он становится потому, что листинг,
      # отклонённый как опрос статуса, иначе уезжает в создание выплаты по
      # одному имени ресурса в пути.
      def method_mismatch?(role)
        return false unless book.veto(:http_method)[:roles].include?(role)

        methods = book.entry(role)[:http_methods]
        !methods.empty? && !methods.include?(@http_method)
      end

      def list?(role)
        @list && book.veto(:list_response)[:roles].include?(role)
      end
    end
  end
end
