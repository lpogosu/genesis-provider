# frozen_string_literal: true

RSpec.describe SpecGen::Generators::Ruby do
  describe '.str' do
    it 'prefers single quotes and escapes backslashes so that the literal evaluates to the text' do
      literal = described_class.str('^7\d{10}$')
      expect(literal).to start_with("'").and end_with("'")
      expect(eval(literal)).to eq('^7\d{10}$') # rubocop:disable Security/Eval
    end

    it 'switches to double quotes when the text has an apostrophe' do
      expect(described_class.str("it's")).to eq('"it\'s"')
    end
  end

  describe '.sym' do
    it 'quotes symbols that are not plain identifiers' do
      expect(described_class.sym('in_progress')).to eq(':in_progress')
      expect(described_class.sym('payout.completed')).to eq(':"payout.completed"')
    end
  end

  describe '.regexp' do
    it 'uses slashes unless the pattern contains one' do
      expect(described_class.regexp('^7\d{10}$')).to eq('/^7\d{10}$/')
      expect(described_class.regexp('^a/b$')).to eq('%r{^a/b$}')
      expect(described_class.regexp('^a/{2}$')).to eq("Regexp.new('^a/{2}$')")
    end
  end

  describe '.array' do
    it 'picks %w and %i for simple words and falls back to brackets otherwise' do
      expect(described_class.array(%w[sbp card])).to eq('%w[sbp card]')
      expect(described_class.array(%i[retry retry_backoff])).to eq('%i[retry retry_backoff]')
      expect(described_class.array([429, 500])).to eq('[429, 500]')
      expect(described_class.array(['a b'])).to eq("['a b']")
    end
  end

  describe '.number' do
    it 'separates every three digits of an integer from 10000 up' do
      expect(described_class.number(10_000)).to eq('10_000')
      expect(described_class.number(5_000_000)).to eq('5_000_000')
      expect(described_class.number(999)).to eq('999')
      expect(described_class.number(9999)).to eq('9999')
    end

    it 'keeps the sign and groups only the whole part of a fraction' do
      expect(described_class.number(-12_345)).to eq('-12_345')
      expect(described_class.number(1234.56)).to eq('1234.56')
      expect(described_class.number(12_345.678)).to eq('12_345.678')
      expect(described_class.number(Rational(100_000, 100))).to eq('1000.0')
    end

    it 'is what .literal uses for numbers so that no generator prints a bare one' do
      expect(described_class.literal(250_000)).to eq('250_000')
      expect(described_class.literal([1_000_000, 'x'])).to eq("[1_000_000, 'x']")
    end
  end

  describe '.guard' do
    it 'keeps a short guard on one line and expands a long one into if/end with a blank line' do
      expect(described_class.guard('x', 'y', indent: 6)).to eq(['return x if y'])
      long = described_class.guard('failure(:a_very_long_code, \'errors.a_very_long_code\')',
                                   'operation.recipient_phone.to_s.match?(/^7\d{10}$/)', indent: 6, negate: true)
      expect(long).to eq(['unless operation.recipient_phone.to_s.match?(/^7\d{10}$/)',
                          "  return failure(:a_very_long_code, 'errors.a_very_long_code')", 'end', ''])
    end
  end

  describe '.comment' do
    it 'wraps by words within the width and keeps an empty paragraph as a bare #' do
      lines = described_class.comment("aaa bbb ccc\n\nddd", width: 9)
      expect(lines).to eq(['# aaa bbb', '# ccc', '#', '# ddd'])
    end
  end

  describe '.words' do
    it 'wraps a %w literal aligning continuation lines with the first element' do
      expect(described_class.words(%w[one two three four], width: 14))
        .to eq(['%w[one two', '   three four]'])
    end
  end

  describe '.indent' do
    it 'moves rescue to the def level and leaves blank lines empty' do
      expect(described_class.indent(['a', '', 'rescue X', 'b'], 6)).to eq(['      a', '', '    rescue X', '      b'])
    end
  end

  describe '.snake' do
    it 'turns operationId and paths into identifiers' do
      expect(described_class.snake('getPayoutStatus')).to eq('get_payout_status')
      expect(described_class.snake('POST /payouts/{id}/cancel')).to eq('post_payouts_id_cancel')
      expect(described_class.snake('42abc')).to eq('op_42abc')
    end
  end
end
