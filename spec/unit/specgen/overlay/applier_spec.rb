# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::Overlay::Applier do
  # Документ, к которому применяются действия: только то, что нужно
  # примерам, но со строковыми ключами, как их отдаёт загрузчик.
  def document
    { 'openapi' => '3.0.3', 'info' => { 'title' => 'Acme Payouts', 'version' => '1.2.0' },
      'servers' => [{ 'url' => 'https://sandbox.acme.test' }],
      'paths' => { '/payouts' => { 'post' => operation } },
      'components' => { 'schemas' => { 'Recipient' => recipient } } }
  end

  def operation
    { 'operationId' => 'createPayout',
      'parameters' => [{ 'name' => 'X-Trace', 'in' => 'header' },
                       { 'name' => 'X-Debug', 'in' => 'header' }],
      'responses' => { '201' => { 'description' => 'created' } } }
  end

  def recipient
    { 'type' => 'object', 'required' => %w[type],
      'properties' => { 'type' => { 'type' => 'string', 'enum' => %w[sbp card] },
                        'phone' => { 'type' => 'string', 'maxLength' => 16 } } }
  end

  def apply(text, data = document)
    result = Dir.mktmpdir('specgen-overlay') do |dir|
      path = File.join(dir, 'acme.overlay.yaml')
      File.binwrite(path, text)
      SpecGen::Overlay.apply(data, file: path)
    end
    [result, data]
  end

  def overlay(*actions)
    "overlay: 1.0.0\ninfo:\n  title: acme\n  version: 1.0.0\nactions:\n#{actions.join}"
  end

  describe 'update' do
    it 'adds a keyword the specification never had, without calling it a conflict' do
      result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient"
          update:
            dependentRequired:
              type: [bank_code]
      YAML

      expect(data['components']['schemas']['Recipient']['dependentRequired']).to eq('type' => ['bank_code'])
      expect(result.conflicts).to be_empty
      expect(result.applied.map(&:target)).to eq(['$.components.schemas.Recipient'])
      expect(result.applied.first.kind).to eq(:update)
    end

    it 'merges nested objects instead of replacing them' do
      _result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient"
          update:
            properties:
              phone:
                pattern: "^\\\\+7\\\\d{10}$"
      YAML

      phone = data['components']['schemas']['Recipient']['properties']['phone']
      expect(phone).to eq('type' => 'string', 'maxLength' => 16, 'pattern' => '^\\+7\\d{10}$')
      expect(data['components']['schemas']['Recipient']['properties']).to have_key('type')
    end

    it 'replaces an array whole, as the Overlay merge rule says' do
      _result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient"
          update:
            required: [type, phone]
      YAML

      expect(data['components']['schemas']['Recipient']['required']).to eq(%w[type phone])
    end

    it 'assigns null rather than deleting the property: this is not JSON Merge Patch' do
      _result, data = apply(overlay(<<~YAML))
        - target: "$.info"
          update:
            version: ~
      YAML

      expect(data['info']).to have_key('version')
      expect(data['info']['version']).to be_nil
    end

    it 'records a conflict when it overrides a value the specification stated otherwise' do
      result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient.properties.phone"
          update:
            maxLength: 32
      YAML

      expect(data['components']['schemas']['Recipient']['properties']['phone']['maxLength']).to eq(32)
      change = result.conflicts.first
      expect(result.conflicts.size).to eq(1)
      expect(change.json_path).to eq('$.components.schemas.Recipient.properties.phone.maxLength')
      expect(change.before_text).to eq('16')
      expect(change.after_text).to eq('32')
      expect(change).not_to be_removed
    end

    it 'says nothing when the overlay repeats what the specification already says' do
      result, = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient.properties.phone"
          update:
            maxLength: 16
      YAML

      expect(result.conflicts).to be_empty
      expect(result.applied.size).to eq(1)
    end

    it 'appends to an array target, as the Action Object of Overlay 1.0.0 describes' do
      _result, data = apply(overlay(<<~YAML))
        - target: "$.servers"
          update:
            url: https://api.acme.test
      YAML

      expect(data['servers'].map { |server| server['url'] })
        .to eq(['https://sandbox.acme.test', 'https://api.acme.test'])
    end

    it 'refuses a scalar target: an object cannot be merged into a string' do
      expect { apply(overlay("- target: \"$.info.title\"\n  update:\n    x: 1\n")) }
        .to raise_error(SpecGen::OverlayError) do |error|
          expect(error.path).to eq('$.info.title')
          expect(error.message).to match(/цель указывает на string/)
        end
    end
  end

  describe 'remove' do
    it 'takes a node out of the object that holds it and records what was there' do
      result, data = apply(overlay("- target: \"$.components.schemas.Recipient.properties.phone\"\n  remove: true\n"))

      expect(data['components']['schemas']['Recipient']['properties'].keys).to eq(['type'])
      expect(result.applied.first.kind).to eq(:remove)
      expect(result.conflicts.first).to be_removed
      expect(result.conflicts.first.json_path)
        .to eq('$.components.schemas.Recipient.properties.phone')
    end

    it 'takes an element out of the array that holds it' do
      _result, data = apply(overlay("- target: \"$.paths['/payouts'].post.parameters[0]\"\n  remove: true\n"))

      expect(data['paths']['/payouts']['post']['parameters'].map { |p| p['name'] }).to eq(['X-Debug'])
    end
  end

  describe 'a target that matches nothing' do
    it 'skips the action, applies the rest and remembers the miss' do
      result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Sender"
          update:
            description: gone
        - target: "$.info"
          update:
            description: still applied
      YAML

      expect(result.misses).to eq(['$.components.schemas.Sender'])
      expect(result.applied.map(&:target)).to eq(['$.info'])
      expect(data['info']['description']).to eq('still applied')
      expect(data['components']['schemas']).not_to have_key('Sender')
    end
  end

  describe 'order' do
    it 'applies actions in file order, so a later action sees what an earlier one wrote' do
      result, data = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Recipient"
          update:
            dependentRequired:
              type: [bank_code]
        - target: "$.components.schemas.Recipient.dependentRequired"
          update:
            type: [card_number]
      YAML

      expect(data['components']['schemas']['Recipient']['dependentRequired']).to eq('type' => ['card_number'])
      expect(result.conflicts.map(&:json_path))
        .to eq(['$.components.schemas.Recipient.dependentRequired.type'])
    end
  end

  describe 'what the profile learns' do
    it 'turns misses and overrides into warnings and blocks nothing' do
      profile = SpecGen::IR::ProviderProfile.new
      result, = apply(overlay(<<~YAML))
        - target: "$.components.schemas.Sender"
          update:
            description: gone
        - target: "$.components.schemas.Recipient.properties.phone"
          update:
            maxLength: 32
        - target: "$.components.schemas.Recipient.properties.type"
          remove: true
      YAML
      result.warn_into(profile)

      expect(profile.warnings.map(&:code))
        .to contain_exactly(:overlay_target_missing, :overlay_conflict, :overlay_conflict)
      expect(profile.warnings.map(&:severity).uniq).to eq([:warning])
      missing = profile.warnings.find { |w| w.code == :overlay_target_missing }
      expect(missing.json_path).to eq('$.components.schemas.Sender')
      expect(missing.message).to include('acme.overlay.yaml')
      expect(profile.warnings.map(&:message).join)
        .to match(/заменил значение.*было 16, стало 32/m).and match(/удалил узел/)
    end
  end
end
