# frozen_string_literal: true

# Paths to spec fixtures, so examples never build them by hand.
module Fixtures
  ROOT = File.join(SpecGen::ROOT, 'spec', 'fixtures').freeze

  # @param name [String] file under spec/fixtures/specs
  def spec_fixture(name)
    File.join(ROOT, 'specs', name)
  end

  # @param name [String] file under spec/fixtures/bad
  def bad_fixture(name)
    File.join(ROOT, 'bad', name)
  end

  # @param name [String] file under spec/fixtures/good
  def good_fixture(name)
    File.join(ROOT, 'good', name)
  end
end
