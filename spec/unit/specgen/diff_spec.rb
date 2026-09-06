# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::Diff do
  include Fixtures
  include IRBuilders

  def rules
    @rules ||= SpecGen::Rules.load
  end

  def profile_of(file, overlay: nil)
    document = SpecGen::SpecLoader.load(file, overlay: overlay)
    SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: {})
  end

  def marks(changes)
    changes.map { |change| [change.kind, change.impact] }
  end

  def only(changes, kind)
    changes.select { |change| change.kind == kind }
  end

  let(:novapay) { profile_of(spec_fixture('novapay.yaml')) }
  let(:overlaid) do
    profile_of(spec_fixture('novapay.yaml'), overlay: File.join(Fixtures::ROOT, 'overlays',
                                                                'novapay.yaml'))
  end
  let(:version_two) { profile_of(good_fixture('novapay_v2.yaml')) }

  describe 'a specification against itself' do
    it 'finds nothing at all' do
      expect(described_class.call(novapay, profile_of(spec_fixture('novapay.yaml')))).to be_empty
    end

    it 'finds nothing in any of the shipped specifications, foreign ones included' do
      %w[cardpay.yaml depositbank.yaml broken.yaml].each do |name|
        profile = profile_of(spec_fixture(name))
        expect(described_class.call(profile, profile_of(spec_fixture(name)))).to be_empty, name
      end
    end

    # Версия документа, заголовок и проза — не изменение интеграции. Иначе
    # каждый выпуск спецификации давал бы отчёт, который нечего читать.
    it 'ignores the version of the document and the prose of a summary' do
      Dir.mktmpdir('specgen-diff') do |dir|
        file = File.join(dir, 'reworded.yaml')
        text = File.read(spec_fixture('novapay.yaml'))
                   .sub('version: 1.0.0', 'version: 2.4.0')
                   .sub('summary: Получить статус выплаты', 'summary: Проверить статус выплаты')
        File.binwrite(file, text)

        expect(described_class.call(novapay, profile_of(file))).to be_empty
      end
    end
  end

  describe 'a specification against its own overlay' do
    # Overlay говорит формально то, что спецификация сказала прозой: условие
    # то же, меняется только его источник, и ветка в сервисе остаётся прежней.
    it 'finds the conditional requirement it made formal, and nothing besides' do
      changes = described_class.call(novapay, overlaid)

      expect(marks(changes)).to eq([%i[field_condition_origin_changed docs]] * 2)
      expect(changes.map(&:json_path))
        .to eq(['$.components.schemas.Recipient.properties.bank_code',
                '$.components.schemas.Recipient.properties.card_number'])
      expect(changes.first.before).to eq(:description_hint)
      expect(changes.first.after).to eq(:x_jsonschema_if)
    end

    it 'calls none of it a change of the generated service' do
      expect(described_class.call(novapay, overlaid).none?(&:code?)).to be(true)
    end
  end

  describe 'a specification against its next version' do
    subject(:changes) { described_class.call(novapay, version_two) }

    it 'finds every planted difference and calls each one a change of the service' do
      expect(marks(changes)).to eq([%i[operation_added code], %i[status_added code],
                                    %i[status_removed code], %i[error_added code],
                                    %i[signature_encoding_changed code],
                                    %i[signature_header_changed code],
                                    %i[signature_payload_changed code],
                                    %i[parameter_added code], %i[parameter_added code],
                                    %i[parameter_removed code]])
    end

    it 'names the new operation by its key and by the endpoint it appeared at' do
      change = only(changes, :operation_added).first
      expect(change.after).to eq('retryPayout')
      expect(change.json_path).to eq("$.paths['/payouts/{payout_id}/retry'].post")
    end

    # Переименование статуса — это пара «исчез — появился»: STATUS_MAP
    # сгенерированного сервиса ключуется именем, и другого имени он не узнает.
    it 'reads a renamed status as one status gone and another one arrived' do
      expect(only(changes, :status_removed).first.before).to eq('completed = approved')
      expect(only(changes, :status_added).first.after).to eq('succeeded = approved')
    end

    it 'finds the new required header of the operation that creates a payout' do
      change = only(changes, :parameter_added).find { |item| item.after == 'X-Client-Id' }
      expect(change.json_path).to eq("$.paths['/payouts'].post.parameters[1]")
      expect(change.impact).to eq(:code)
    end

    # Переименованный заголовок уводит подпись из профиля справочника, и
    # вместе с именем теряются кодирование и подписываемое тело. Отчёт обязан
    # сказать и это: иначе verify_signature! перегенерируется молча.
    it 'reports what the renamed signature header took with it' do
      expect(only(changes, :signature_header_changed).first.before).to eq('X-NovaPay-Signature')
      expect(only(changes, :signature_header_changed).first.after).to eq('X-Signature')
      expect(only(changes, :signature_encoding_changed).first.after).to be_nil
    end

    it 'finds the error code that the enum gained' do
      expect(only(changes, :error_added).first.after).to eq('recipient_blocked = reject')
    end

    it 'is deterministic: the same pair of profiles gives the same order twice' do
      expect(changes.map(&:sort_key)).to eq(described_class.call(novapay, version_two)
                                                           .map(&:sort_key))
    end

    it 'sorts by area, then by address, then by kind' do
      areas = changes.map { |change| SpecGen::Diff::Change::AREAS.index(change.area) }
      expect(areas).to eq(areas.sort)
    end
  end

  describe 'a value that nobody derived' do
    def status_profile(status, internal)
      SpecGen::IR::ProviderProfile.new(
        status_map: [SpecGen::IR::StatusMapping.new(provider_status: status, internal: internal,
                                                    json_path: '$.x')]
      )
    end

    let(:unknown) { SpecGen::IR::Derived.unknown(evidence: 'синонима нет ни в одном справочнике') }

    # Неоднозначный вход: обе версии не смогли вывести внутренний статус.
    # Сказать «изменилось» здесь значило бы выдать два незнания за событие.
    it 'stays silent when the value was underived in both versions' do
      changes = described_class.call(status_profile('PART_DONE', unknown),
                                     status_profile('PART_DONE', unknown))
      expect(changes).to be_empty
    end

    it 'reports the loss when a value stops being derived' do
      changes = described_class.call(status_profile('PART_DONE', structural(:approved)),
                                     status_profile('PART_DONE', unknown))
      expect(changes.map(&:kind)).to eq([:status_internal_changed])
      expect(changes.first.after).to eq('PART_DONE = —')
    end

    # Уверенность и происхождение сравнивать нельзя: множитель, посчитанный
    # по эвристике 0.43, и он же по структуре — один и тот же множитель.
    it 'ignores a change of source when the value itself stayed the same' do
      guess = SpecGen::IR::Derived.heuristic('RUB', confidence: 0.43, evidence: 'поле amt')
      read = SpecGen::IR::ProviderProfile.new(units: units)
      guessed = SpecGen::IR::ProviderProfile.new(
        units: SpecGen::IR::Units.new(currency: guess, unit: structural(:minor, 'type: integer'),
                                      exponent: SpecGen::IR::Derived.registry(2, evidence: 'ISO'))
      )
      expect(described_class.call(read, guessed)).to be_empty
    end
  end

  describe 'a profile that has nothing in it' do
    it 'compares two empty profiles without raising and without inventing changes' do
      expect(described_class.call(SpecGen::IR::ProviderProfile.new,
                                  SpecGen::IR::ProviderProfile.new)).to be_empty
    end

    # Спецификация, потерявшая авторизацию, обязана сказать об этом одной
    # строкой, а не промолчать из-за nil.
    it 'reads a whole section that disappeared as a value that became nothing' do
      changes = described_class.call(novapay, SpecGen::IR::ProviderProfile.new)
      types = only(changes, :auth_type_changed)
      expect(types.size).to eq(1)
      expect(types.first.before).to eq(:api_key)
      expect(types.first.after).to be_nil
    end
  end

  describe SpecGen::Diff::Change do
    it 'fills the area and the impact from the kind' do
      change = described_class.build(:status_added, json_path: '$.x', after: 'paid = approved')
      expect([change.area, change.impact]).to eq(%i[statuses code])
    end

    it 'refuses a kind that is not in the vocabulary instead of inventing an area' do
      expect { described_class.build(:everything_changed, json_path: '$.x') }
        .to raise_error(ArgumentError, /everything_changed/)
    end

    it 'refuses an impact outside the closed list' do
      expect { described_class.build(:status_added, json_path: '$.x', impact: :maybe) }
        .to raise_error(ArgumentError, /maybe/)
    end

    it 'gives every kind an area of the fixed list' do
      areas = described_class::KINDS.values.map(&:first).uniq
      expect(areas - described_class::AREAS).to be_empty
    end
  end
end
