# frozen_string_literal: true

module SpecGen
  module Rules
    # Every dictionary, loaded and cross-checked as one unit.
    #
    # Loading is all or nothing. If a file is missing, malformed, or says
    # something a neighbouring file contradicts, the load raises a single
    # RulesError listing every problem, and the pipeline never starts on half
    # a dictionary. That is the whole point of doing this at startup: a
    # synonym claimed by two roles has to be a failure someone reads, not a
    # coin flip inside a generated payment request.
    class Registry
      BOOKS = {
        roles: RolesBook, statuses: StatusesBook, currencies: CurrenciesBook,
        signatures: SignaturesBook, idempotency: IdempotencyBook, auth: AuthBook,
        contract: ContractBook
      }.freeze

      # @return [String] directory the dictionaries were read from
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
      # @return [ContractBook]
      attr_reader :contract

      # @param dir [String] directory holding the dictionaries
      # @return [Registry]
      # @raise [RulesError]
      def self.load(dir)
        new(dir)
      end

      # @param dir [String]
      # @raise [RulesError] listing every problem in every dictionary
      def initialize(dir)
        @dir = dir
        @problems = Problems.new
        BOOKS.each { |key, klass| instance_variable_set(:"@#{key}", read(klass)) }
        cross_check
        @problems.raise!
        freeze
      end

      # @return [Array<String>] the files that were read
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

      # Two dictionaries may not claim the same name for different meanings:
      # `x_request_id` is either a role synonym or an idempotency header, and
      # whichever way it is read, it has to be read the same way everywhere.
      def cross_check
        return if roles.nil?

        check_names(idempotency&.normalized, :idempotency_key, IdempotencyBook::FILE, 'alias')
        check_names(signatures&.headers, :signature, SignaturesBook::FILE, 'signature header')
      end

      def check_names(names, expected, file, what)
        Array(names).each do |name|
          owner = roles.role_for(name)
          next if owner.nil? || owner == expected

          @problems.add("#{what} #{name.inspect} is claimed by role #{owner} in " \
                        "#{RolesBook::FILE}; a name may mean one thing only", file: file)
        end
      end
    end
  end
end
