# frozen_string_literal: true

# On the shipped dictionaries and weights, like the composite it drives.
RSpec.describe SpecGen::Matchers::Assigner do
  let(:rules) { SpecGen::Rules.load }
  let(:assigner) { described_class.new(rules: rules) }

  def subject_for(name, attributes = {})
    defaults = { type: 'string', parents: ['Thing'], json_path: "$.components.schemas.Thing.properties.#{name}" }
    SpecGen::Matchers::Subject.new(name: name, **defaults.merge(attributes))
  end

  def assign(*subjects)
    assigner.call(subjects)
  end

  def only(name, attributes = {})
    assign(subject_for(name, attributes)).first
  end

  describe 'a confident role' do
    it 'assigns a dictionary hit as registry with no remark' do
      outcome = only('sum', type: 'integer')

      expect(outcome.derived).to have_attributes(value: :amount, source: :registry, confidence: 0.9)
      expect(outcome.derived.evidence).to include('по справочнику: имя `sum` — синоним роли amount')
      expect(outcome.remarks).to be_empty
    end

    it 'assigns a heuristic above the threshold silently, with the arithmetic as evidence' do
      outcome = only('contact', parents: ['Recipient'], constraints: { pattern: '^7\d{10}$' })

      expect(outcome.derived).to have_attributes(value: :recipient_phone, source: :heuristic)
      expect(outcome.derived.confidence).to be >= 0.6
      expect(outcome.derived.evidence)
        .to include('композитное сопоставление: name 2.0 (общие токены с синонимом `contact_phone`')
        .and include('constraint 4.0 (pattern дословно совпадает с шаблоном роли)')
        .and include('= 11.0 из 14.0; других кандидатов нет')
      expect(outcome.remarks).to be_empty
    end
  end

  describe 'a doubtful role' do
    it 'still assigns the best candidate below the threshold, and lists every candidate' do
      outcome = only('payout_amt', type: 'integer')

      expect(outcome.derived).to have_attributes(value: :amount, source: :heuristic)
      expect(outcome.derived.confidence).to be_within(0.01).of(6.0 / 14)
      expect(outcome.remarks.size).to eq(1)
      expect(outcome.remarks.first).to have_attributes(code: :field_role_low_confidence, severity: :info)
      expect(outcome.remarks.first.message)
        .to include('необязательное поле `payout_amt`: роль amount выведена с низкой уверенностью 0.43 (порог 0.60)')
        .and include('кандидаты: amount 0.43')
      expect(outcome.remarks.first.suggested_overlay)
        .to include('- target: "$.components.schemas.Thing.properties.payout_amt"', 'x-specgen-role: amount')
    end

    it 'warns instead of informing when the doubtful field is required' do
      remark = only('payout_amt', type: 'integer', required: true).remarks.first

      expect(remark.severity).to eq(:warning)
      expect(remark.message).to include('обязательное поле `payout_amt`').and include('с TODO')
    end

    it 'lists every candidate of a tie below the threshold, and still picks the first by role order' do
      outcome = only('phone_card', parents: ['Recipient'])

      expect(outcome.derived.value).to eq(:recipient_phone)
      expect(outcome.remarks.first.code).to eq(:field_role_low_confidence)
      expect(outcome.remarks.first.message).to include('кандидаты: recipient_phone 0.50, card_number 0.50')
    end
  end

  describe 'no role' do
    it 'leaves a field nobody voted for unknown, with a TODO slot in the overlay' do
      outcome = only('xref_tag_9', constraints: { max_length: 64 })

      expect(outcome.derived).to be_unknown
      expect(outcome.derived.evidence).to include('ни имя, ни ограничения не совпали')
      expect(outcome.remarks.first).to have_attributes(code: :field_role_unknown, severity: :info)
      expect(outcome.remarks.first.message).to include('необязательное поле `xref_tag_9` (string, max_length 64)')
      expect(outcome.remarks.first.suggested_overlay).to include('x-specgen-role: TODO')
    end

    it 'tells a required field without a role apart from an optional one' do
      required = only('xref_tag_9', required: true).remarks.first
      optional = only('xref_tag_9').remarks.first

      expect(required).to have_attributes(code: :required_field_role_unknown, severity: :warning)
      expect(required.message).to include('без него запрос не уйдёт')
      expect(optional).to have_attributes(code: :field_role_unknown, severity: :info)
      expect(optional.message).to include('в запрос оно не попадёт')
    end

    it 'gives a container no role and no remark: its nested fields take the roles' do
      outcome = only('recipient', type: 'object', container: true)

      expect(outcome.derived).to be_unknown
      expect(outcome.derived.evidence).to include('поле-контейнер (object)')
      expect(outcome.remarks).to be_empty
    end
  end

  describe 'x-specgen-role' do
    it 'wins over everything, as an overlay source' do
      outcome = only('xref_tag_9', overlay: 'bank_code')

      expect(outcome.derived).to have_attributes(value: :bank_code, source: :overlay, confidence: 1.0)
      expect(outcome.remarks).to be_empty
    end

    it 'rejects a value outside the vocabulary and falls back to the matchers' do
      outcome = only('sum', overlay: 'mood')

      expect(outcome.derived.value).to eq(:amount)
      expect(outcome.remarks.first).to have_attributes(code: :spec_element_unsupported)
      expect(outcome.remarks.first.message).to include('x-specgen-role: неизвестная роль "mood"')
    end
  end

  describe 'one role for two fields of one schema' do
    it 'keeps the role at the stronger field and demotes the other to its next candidate' do
      first, second = assign(subject_for('transaction_id'),
                             subject_for('payout_batch_ref', parents: ['payout_batch']))

      expect(first.derived).to have_attributes(value: :provider_operation_id, source: :registry)
      expect(first.remarks).to be_empty
      expect(second.derived).to be_unknown
      expect(second.derived.evidence).to include('роль provider_operation_id отдана `transaction_id` (0.90)')
      expect(second.remarks.first).to have_attributes(code: :field_role_conflict, severity: :info)
      expect(second.remarks.first.message)
        .to include('`payout_batch_ref`: роль provider_operation_id (0.50) уже у `transaction_id` (0.90)')
        .and include('других кандидатов нет')
    end

    it 'hands the loser its next candidate when it has one' do
      first, second = assign(subject_for('phone', parents: ['Recipient']),
                             subject_for('phone_card', parents: ['Recipient']))

      expect(first.derived.value).to eq(:recipient_phone)
      expect(second.derived.value).to eq(:card_number)
      expect(second.derived.evidence).to start_with('роль recipient_phone отдана `phone` (0.90); ')
      expect(second.remarks.first.message).to include('взята следующая роль card_number (0.50)')
    end

    it 'lets the earlier field win a tie and never questions an overlay role' do
      first, second = assign(subject_for('id'), subject_for('payout_id'))
      fixed, other = assign(subject_for('a', overlay: 'amount'), subject_for('sum'))

      expect(first.derived.value).to eq(:provider_operation_id)
      expect(second.derived).to be_unknown
      expect(fixed.derived.source).to eq(:overlay)
      expect(other.derived).to be_unknown
      expect(other.remarks.first.code).to eq(:field_role_conflict)
    end

    it 'survives a chain of conflicts where the first winner later loses' do
      outcomes = nil

      expect { outcomes = assign(subject_for('payout_id'), subject_for('id'), subject_for('transaction_id')) }
        .not_to raise_error
      expect(outcomes.map { |outcome| outcome.derived.value }).to eq([:provider_operation_id, nil, nil])
    end
  end

  it 'decides the same way on every call' do
    subjects = [subject_for('sum'), subject_for('phone_card', parents: ['Recipient']),
                subject_for('id'), subject_for('payout_id')]

    expect(assigner.call(subjects).map(&:to_h)).to eq(described_class.new(rules: rules).call(subjects).map(&:to_h))
  end
end
