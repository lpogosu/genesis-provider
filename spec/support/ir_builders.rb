# frozen_string_literal: true

# Small IR objects for examples, so each example states only what it tests.
module IRBuilders
  include SpecGen::IR

  def structural(value, evidence = 'spec')
    Derived.structural(value, evidence: evidence)
  end

  def operation(role, http_method, path, **rest)
    Operation.new(role: structural(role, 'operationId'), http_method: http_method, path: path, **rest)
  end

  def error_rule(status, action)
    ErrorRule.new(http_status: status, action: structural(action, "response #{status}"))
  end

  def units
    Units.new(currency: structural('RUB', 'enum: [RUB]'), unit: structural(:minor, 'type: integer'),
              exponent: Derived.registry(2, evidence: 'ISO 4217: RUB exponent 2'))
  end

  def info
    Info.new(name: structural('acmepay', '--provider'), oas_version: '3.0.3', oas_family: :oas30,
             title: 'Acme Payout API')
  end

  # A profile with one of everything, built either in declaration order or in
  # reverse, to prove the serialised form does not depend on insertion order.
  def full_profile(reverse: false)
    profile = ProviderProfile.new(info: info, units: units)
    fill_operations(profile, reverse)
    fill_maps(profile, reverse)
    fill_warnings(profile, reverse)
    profile
  end

  private

  def fill_operations(profile, reverse)
    operations = [operation(:create_payout, :post, '/payouts', id: 'createPayout'),
                  operation(:balance, :get, '/balance')]
    schemas = { 'Payout' => Schema.new(name: 'Payout'), 'Error' => Schema.new(name: 'Error') }
    profile.operations.concat(reverse ? operations.reverse : operations)
    (reverse ? schemas.to_a.reverse : schemas.to_a).each { |name, schema| profile.schemas[name] = schema }
  end

  def fill_maps(profile, reverse)
    statuses = [StatusMapping.new(provider_status: 'pending', internal: structural(:in_progress, 'canon')),
                StatusMapping.new(provider_status: 'completed', internal: structural(:approved, 'canon'))]
    rules = [error_rule(402, :retry), error_rule(500, :retry_backoff)]
    profile.status_map.concat(reverse ? statuses.reverse : statuses)
    profile.error_map.concat(reverse ? rules.reverse : rules)
  end

  def fill_warnings(profile, reverse)
    entries = [[:units_inconsistent, 'minimum disagrees with the description', :warning, '$.b'],
               [:operation_unmapped, 'GET /balance is not part of the contract', :info, '$.a']]
    (reverse ? entries.reverse : entries).each do |code, message, severity, path|
      profile.warn(code, message, severity: severity, json_path: path)
    end
  end

  # @return [Boolean] true when the structure holds no IR objects any more
  def plain?(value)
    case value
    when Hash then value.all? { |key, item| (key.is_a?(Symbol) || key.is_a?(String)) && plain?(item) }
    when Array then value.all? { |item| plain?(item) }
    when SpecGen::IR::Node then false
    else true
    end
  end
end
