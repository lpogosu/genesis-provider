# frozen_string_literal: true

# Маленькие объекты IR для примеров, чтобы каждый пример говорил только о
# том, что он проверяет.
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
              exponent: Derived.registry(2, evidence: 'ISO 4217: экспонента RUB 2'))
  end

  def info
    Info.new(name: structural('acmepay', '--provider'), oas_version: '3.0.3', oas_family: :oas30,
             title: 'Acme Payout API')
  end

  # Профиль, в котором есть по одному всему, собранный либо в порядке
  # объявления, либо в обратном, — чтобы доказать, что сериализованный вид не
  # зависит от порядка вставки.
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
    statuses = [StatusMapping.new(provider_status: 'pending', internal: structural(:in_progress, 'канон кейса')),
                StatusMapping.new(provider_status: 'completed', internal: structural(:approved, 'канон кейса'))]
    rules = [error_rule(402, :retry), error_rule(500, :retry_backoff)]
    profile.status_map.concat(reverse ? statuses.reverse : statuses)
    profile.error_map.concat(reverse ? rules.reverse : rules)
  end

  def fill_warnings(profile, reverse)
    entries = [[:units_inconsistent, 'minimum расходится с описанием', :warning, '$.b'],
               [:operation_unmapped, 'GET /balance не входит в контракт', :info, '$.a']]
    (reverse ? entries.reverse : entries).each do |code, message, severity, path|
      profile.warn(code, message, severity: severity, json_path: path)
    end
  end

  # @return [Boolean] true, если в структуре больше не осталось объектов IR
  def plain?(value)
    case value
    when Hash then value.all? { |key, item| (key.is_a?(Symbol) || key.is_a?(String)) && plain?(item) }
    when Array then value.all? { |item| plain?(item) }
    when SpecGen::IR::Node then false
    else true
    end
  end
end
