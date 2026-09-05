# frozen_string_literal: true

require 'tmpdir'

# Битый файл overlay — ошибка стадии, а не предупреждение профиля: человек
# написал и подключил его руками, и прогон «как будто переопределений не
# было» соврал бы молча. Каждый пример проверяет три вещи сразу: класс из
# нашей иерархии, имя файла overlay и место внутри него.
RSpec.describe SpecGen::Overlay::Document do
  def overlay_fixture(name)
    File.join(Fixtures::ROOT, 'overlays', name)
  end

  def read(text)
    Dir.mktmpdir('specgen-overlay') do |dir|
      path = File.join(dir, 'test.overlay.yaml')
      File.binwrite(path, text)
      described_class.read(path)
    end
  end

  def expect_refusal(text, path:, message:)
    expect { read(text) }.to raise_error(SpecGen::OverlayError) do |error|
      expect(error.file).to end_with('test.overlay.yaml')
      expect(error.path).to eq(path)
      expect(error.message).to match(message)
    end
  end

  describe 'a file that cannot be read as an overlay at all' do
    it 'refuses a file that is not there, naming it' do
      expect { described_class.read('no/such/file.yaml') }
        .to raise_error(SpecGen::OverlayError, %r{no/such/file\.yaml.*файл не найден})
    end

    it 'refuses broken YAML with the line and the column' do
      expect { described_class.read(overlay_fixture('bad/not_yaml.yaml')) }
        .to raise_error(SpecGen::OverlayError) do |error|
          expect(error.path).to match(/\Aстрока \d+, столбец \d+\z/)
          expect(error.message).to match(/ошибка синтаксиса YAML/)
        end
    end

    it 'refuses a specification handed in instead of an overlay' do
      expect { described_class.read(overlay_fixture('bad/not_overlay.yaml')) }
        .to raise_error(SpecGen::OverlayError, /это не документ OpenAPI Overlay.*openapi, info, paths/)
    end

    it 'refuses a version of the format it cannot promise to apply' do
      expect_refusal("overlay: 2.0.0\nactions: []\n",
                     path: '$.overlay', message: /версия overlay "2\.0\.0" не поддерживается/)
    end
  end

  describe 'the actions section' do
    it 'refuses an overlay with nothing to apply' do
      expect { described_class.read(overlay_fixture('bad/no_actions.yaml')) }
        .to raise_error(SpecGen::OverlayError, /нет секции `actions`/)
    end

    it 'refuses actions that are not an array' do
      expect_refusal("overlay: 1.0.0\nactions:\n  target: \"$.info\"\n",
                     path: '$.actions', message: /`actions` должна иметь тип array, а не object/)
    end

    it 'refuses an empty actions array, as the specification requires at least one action' do
      expect_refusal("overlay: 1.0.0\nactions: []\n",
                     path: '$.actions', message: /`actions` пуста/)
    end

    it 'refuses an action that is not an object' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - just a string\n",
                     path: '$.actions[0]', message: /действие должно иметь тип object, а не string/)
    end
  end

  describe 'one action' do
    it 'refuses an action without a target, pointing at the action itself' do
      expect { described_class.read(overlay_fixture('bad/action_without_target.yaml')) }
        .to raise_error(SpecGen::OverlayError) do |error|
          expect(error.path).to eq('$.actions[0]')
          expect(error.message).to match(/нет обязательного поля `target`/)
        end
    end

    it 'refuses a target that is not a string' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - target: 42\n    update: {}\n",
                     path: '$.actions[0]', message: /`target` должно иметь тип string, а не number/)
    end

    it 'refuses JSONPath beyond the subset, listing the forms it does read' do
      expect { described_class.read(overlay_fixture('bad/unsupported_target.yaml')) }
        .to raise_error(SpecGen::OverlayError) do |error|
          expect(error.path).to eq('$.actions[0]')
          expect(error.message).to match(/синтаксисом JSONPath, который мы не разбираем/)
          expect(error.message).to include('$.components.schemas.X.properties.Y')
        end
    end

    it 'refuses an action that asks for both update and remove instead of doing half of it' do
      expect { described_class.read(overlay_fixture('bad/update_and_remove.yaml')) }
        .to raise_error(SpecGen::OverlayError, /сразу `update` и `remove`/)
    end

    it 'refuses an action that asks for nothing' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - target: \"$.info\"\n",
                     path: '$.actions[0]', message: /не просит ничего/)
    end

    it 'refuses a non-boolean remove' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - target: \"$.info\"\n    remove: yes please\n",
                     path: '$.actions[0]', message: /`remove` должно иметь тип boolean/)
    end

    it 'refuses an update that is not an object' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - target: \"$.info\"\n    update: 5\n",
                     path: '$.actions[0]', message: /`update` должно иметь тип object, а не number/)
    end

    it 'refuses removing the root, which nothing contains' do
      expect_refusal("overlay: 1.0.0\nactions:\n  - target: \"$\"\n    remove: true\n",
                     path: '$.actions[0]', message: /корень документа нельзя удалить/)
    end
  end

  describe 'a well-formed overlay' do
    it 'keeps the actions in file order and reads their intent' do
      overlay = described_class.read(overlay_fixture('novapay.yaml'))
      expect(overlay.version).to eq('1.0.0')
      expect(overlay.title).to eq('NovaPay disambiguation')
      expect(overlay.actions.map(&:kind)).to eq([:update])
      expect(overlay.actions.first.target.to_s).to eq('$.components.schemas.Recipient')
      expect(overlay.actions.first.description).to match(/Условная обязательность/)
    end

    it 'takes the title from the file name when info says nothing, since info changes no result' do
      overlay = read("overlay: 1.0.0\nactions:\n  - target: \"$.info\"\n    update: {}\n")
      expect(overlay.title).to eq('test.overlay.yaml')
    end

    it 'accepts any patch of the 1.0 format' do
      expect(read("overlay: 1.0.3\nactions:\n  - target: \"$\"\n    update: {}\n").version).to eq('1.0.3')
    end
  end
end
