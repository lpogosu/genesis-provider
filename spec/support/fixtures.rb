# frozen_string_literal: true

# Пути к тестовым спецификациям, чтобы примеры не собирали их руками.
module Fixtures
  ROOT = File.join(SpecGen::ROOT, 'spec', 'fixtures').freeze

  # @param name [String] файл в spec/fixtures/specs
  def spec_fixture(name)
    File.join(ROOT, 'specs', name)
  end

  # @param name [String] файл в spec/fixtures/bad
  def bad_fixture(name)
    File.join(ROOT, 'bad', name)
  end

  # @param name [String] файл в spec/fixtures/good
  def good_fixture(name)
    File.join(ROOT, 'good', name)
  end
end
