# frozen_string_literal: true

RSpec.describe SpecGen::Rules::ContractBook do
  include RulesFixtures

  def contract(patch = {})
    load_rules('contract.yml' => rule('contract.yml').merge(patch)).contract
  end

  def methods_patch(&)
    patch = rule('contract.yml')
    yield patch['methods']
    patch
  end

  describe 'the contract as data' do
    it 'knows the class to inherit from and that it is an assumption' do
      book = contract

      expect(book.base_class).to eq('Provider::BaseService')
      expect(book.assumption).to include('реального класса нам не выдали')
    end

    it 'renders a signature, so no template spells one out' do
      book = contract

      expect(book.method_spec('create_request').signature)
        .to eq("create_request(operation, request_method = 'create')")
      expect(book.method_spec('process_callback').signature).to eq('process_callback(payload)')
      expect(book.method_spec('check_conditions').call_args).to eq('operation, request_method')
      expect(book.method_spec('check_conditions')).to be_calls_super
    end

    it 'names the helpers by meaning, not by literal' do
      book = contract

      expect(book.helper(:success)).to eq('success')
      expect(book.helper_spec(:failure)[:params].map { |param| param[:name] })
        .to eq(%w[code i18n_key])
    end

    it 'carries the semantics of request_method and the unit of the amount' do
      book = contract

      expect(book.request_method_semantics).to include('не HTTP-метод')
      expect(book.request_method_values).to eq(%w[create status])
      expect(book.amount_unit).to eq(:major)
      expect(book.internal_statuses).to contain_exactly(:in_progress, :approved, :rejected)
    end

    it 'knows which helper moves an operation into which internal status' do
      book = contract

      expect(book.helper_for_status(:approved)).to eq('approve_operation')
      expect(book.helper_for_status(:rejected)).to eq('reject_operation')
      expect(book.helper_for_status(:in_progress)).to be_nil
    end

    it 'refuses two helpers claiming the same internal status' do
      patch = rule('contract.yml')
      patch['helpers']['reject_operation']['status'] = 'approved'

      expect(rules_error('contract.yml' => patch)).to include('approved').and include('approve_operation')
    end
  end

  describe 'the platform section' do
    it 'gives expressions by role and fills %{value} in lookups and writers' do
      platform = contract.platform

      expect(platform.accessor(:amount)).to eq('operation.amount')
      expect(platform.accessor(:signature)).to be_nil
      expect(platform.lookup(:provider_operation_id, "body['id']"))
        .to eq("Operation.find_by(provider_operation_id: body['id'])")
      expect(platform.writer(:provider_operation_id, 'x')).to eq('operation.update(provider_operation_id: x)')
      expect(platform.callback_body).to eq('payload[:body]')
      expect(platform.success_predicate).to eq('success?')
      expect(platform.source).to eq('допущение')
    end

    it 'is optional: a contract without it yields no expressions instead of failing' do
      platform = contract('platform' => nil).platform
      expect(platform.accessor(:amount)).to be_nil
      expect(platform.callback_body).to be_nil
    end

    it 'refuses a role outside the vocabulary and a lookup without %{value}' do
      patch = rule('contract.yml')
      patch['platform']['accessors']['iban'] = 'operation.iban'
      patch['platform']['lookup']['external_id'] = 'Operation.first'

      message = rules_error('contract.yml' => patch)
      expect(message).to include('iban').and include('external_id').and include('%{value}')
    end
  end

  describe 'binding methods to operation roles' do
    it 'finds the method that serves a role' do
      book = contract

      expect(book.method_for(:create_payout).name).to eq('create_request')
      expect(book.method_for(:webhook).name).to eq('process_callback')
    end

    it 'refuses a contract that leaves an operation role unserved' do
      patch = methods_patch { |set| set['fetch_status'].delete('roles') }

      expect(rules_error('contract.yml' => patch))
        .to include('ни один метод не обслуживает fetch_status').and include('roles:')
    end

    it 'refuses two methods claiming the same role' do
      patch = methods_patch { |set| set['check_conditions']['roles'] = ['webhook'] }

      expect(rules_error('contract.yml' => patch))
        .to include('роль операции webhook уже обслуживает')
    end

    it 'refuses a role outside IR::Roles::CONTRACT' do
      patch = methods_patch { |set| set['fetch_status']['roles'] = %w[fetch_status balance] }

      expect(rules_error('contract.yml' => patch)).to include('роль операции: неизвестное значение "balance"')
    end
  end

  describe 'guarding the shape' do
    it 'refuses a method name Ruby would not accept' do
      patch = methods_patch { |set| set['fetch status'] = set.delete('fetch_status') }

      expect(rules_error('contract.yml' => patch)).to include('не похоже на имя метода Ruby')
    end

    it 'refuses a parameter with a default before one without' do
      patch = methods_patch do |set|
        set['create_request']['params'] = [{ 'name' => 'operation', 'default' => 'nil' },
                                           { 'name' => 'request_method' }]
      end

      expect(rules_error('contract.yml' => patch)).to include('должны идти последними')
    end

    it 'refuses a missing helper' do
      patch = rule('contract.yml')
      patch['helpers'].delete('approve_operation')

      expect(rules_error('contract.yml' => patch))
        .to include('не описаны хелперы: approve_operation')
    end

    it 'refuses internal statuses that disagree with IR' do
      patch = rule('contract.yml')
      patch['internal_statuses'] = %w[in_progress approved]

      expect(rules_error('contract.yml' => patch))
        .to include('внутренние статусы должны быть ровно')
    end

    it 'refuses a base class that is not a constant path' do
      expect(rules_error('contract.yml' => rule('contract.yml').merge('base_class' => 'service')))
        .to include('не похож на путь константы Ruby')
    end
  end
end
