# frozen_string_literal: true

module SpecGen
  module Rules
    # Все справочники, загруженные и сверенные между собой как одно целое.
    #
    # Загрузка либо целиком удаётся, либо целиком нет. Если файла нет, он
    # битый или говорит то, чему противоречит соседний файл, загрузка
    # поднимает одну RulesError со списком всех проблем, и конвейер никогда
    # не стартует на половине справочника. В этом весь смысл делать проверку
    # на старте: синоним, занятый двумя ролями, обязан быть отказом, который
    # кто-то прочитает, а не подбрасыванием монетки внутри сгенерированного
    # платёжного запроса.
    class Registry
      BOOKS = {
        roles: RolesBook, statuses: StatusesBook, currencies: CurrenciesBook,
        signatures: SignaturesBook, idempotency: IdempotencyBook, auth: AuthBook,
        operations: OperationsBook, conditions: ConditionsBook,
        contract: ContractBook
      }.freeze

      # @return [String] каталог, из которого прочитаны справочники
      attr_reader :dir
      # @return [RolesBook]
      attr_reader :roles
      # @return [StatusesBook]
      attr_reader :statuses
      # @return [CurrenciesBook]
      attr_reader :currencies
      # @return [SignaturesBook]
      attr_reader :signatures
      # @return [IdempotencyBook]
      attr_reader :idempotency
      # @return [AuthBook]
      attr_reader :auth
      # @return [OperationsBook]
      attr_reader :operations
      # @return [ConditionsBook]
      attr_reader :conditions
      # @return [ContractBook]
      attr_reader :contract

      # @param dir [String] каталог со справочниками
      # @return [Registry]
      # @raise [RulesError]
      def self.load(dir)
        new(dir)
      end

      # @param dir [String]
      # @raise [RulesError] со списком всех проблем во всех справочниках
      def initialize(dir)
        @dir = dir
        @problems = Problems.new
        BOOKS.each { |key, klass| instance_variable_set(:"@#{key}", read(klass)) }
        cross_check
        @problems.raise!
        freeze
      end

      # @return [Array<String>] прочитанные файлы
      def files
        BOOKS.each_value.map { |klass| File.join(dir, klass::FILE) }
      end

      private

      def read(klass)
        klass.new(Document.read(File.join(dir, klass::FILE)), @problems)
      rescue RulesError => e
        @problems.add(e.detail || e.message, file: e.file, path: e.path)
        nil
      end

      # Два справочника не могут занимать одно имя под разные смыслы:
      # `x_request_id` — это либо синоним роли, либо заголовок
      # идемпотентности, и как бы он ни читался, читаться он обязан одинаково
      # всюду.
      def cross_check
        return if roles.nil?

        check_names(idempotency&.normalized, :idempotency_key, IdempotencyBook::FILE,
                    Texts.t('rules.noun.alias_name'))
        check_names(signatures&.headers, :signature, SignaturesBook::FILE,
                    Texts.t('rules.noun.signature_header'))
      end

      def check_names(names, expected, file, what)
        Array(names).each do |name|
          owner = roles.role_for(name)
          next if owner.nil? || owner == expected

          @problems.add(claimed(what, name, owner), file: file)
        end
      end

      def claimed(what, name, owner)
        Texts.t('rules.registry.claimed', what: what, name: name.inspect, owner: owner,
                                          file: RolesBook::FILE)
      end
    end
  end
end
