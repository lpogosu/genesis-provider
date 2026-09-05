# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::Generators::Writer do
  it 'creates the output directory and writes LF-only bytes with one trailing newline' do
    Dir.mktmpdir('specgen-writer') do |root|
      dir = File.join(root, 'nested', 'output')
      path = described_class.new(dir).write('x_service.rb', "a\r\nb\n\n\n")

      expect(path).to eq(File.join(dir, 'x_service.rb'))
      expect(File.binread(path)).to eq("a\nb\n")
    end
  end

  it 'adds the missing final newline' do
    Dir.mktmpdir('specgen-writer') do |dir|
      path = described_class.new(dir).write('f.rb', 'no newline')
      expect(File.binread(path)).to eq("no newline\n")
    end
  end

  it 'turns a filesystem failure into a GenerationError naming the path, not a stack trace' do
    Dir.mktmpdir('specgen-writer') do |root|
      blocker = File.join(root, 'taken')
      File.write(blocker, 'a file where a directory is expected')

      expect { described_class.new(blocker).write('f.rb', 'x') }
        .to raise_error(SpecGen::GenerationError) { |error| expect(error.file).to include('taken') }
    end
  end
end
