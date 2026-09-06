# frozen_string_literal: true

# Инвариант конституции проекта: ядро работает с ролями и читает справочники,
# всё провайдер-специфичное живёт в rules/ и в overlay-файлах. Правило было
# записано в docs/PRINCIPLES.md, но не проверялось ничем, и один комментарий его уже
# успел нарушить. Проверка дешевле уговора.
RSpec.describe 'provider neutrality of the core' do
  # Имя выданного провайдера и термины его предметной области. Появление
  # любого из них в lib/ означает ветку по провайдеру вместо строки в
  # справочнике — ровно то, что docs/PRINCIPLES.md запрещает.
  #
  # `bank_code` — исключение с оговоркой: docs/PRINCIPLES.md запрещает это слово в
  # lib/ и он же перечисляет `bank_code` среди ролей, которые хранит IR.
  # Запрет метил в ветку по имени поля, а не в имя роли, поэтому слово
  # разрешено ровно в одном файле — словаре ролей. Везде ещё оно означает
  # именно то, что запрещено.
  forbidden = /novapay|\bsbp\b|bank_code/i

  # Имена чужих публичных спецификаций. В коде их быть не может по той же
  # причине; в комментариях они допустимы как обоснование правила — замер
  # без названия спецификации проверить нельзя.
  corpus = /adyen|paystack|paypal|mollie|govuk|moov|stripe|yookassa/i

  # Единственный файл, которому имя роли разрешено: сам словарь ролей.
  role_vocabulary = 'lib/specgen/ir/roles.rb'

  let(:sources) do
    Dir.glob(File.join(SpecGen::ROOT, 'lib', '**', '*.rb')).to_h do |path|
      relative = Pathname.new(path).relative_path_from(Pathname.new(SpecGen::ROOT))
      [relative.to_s.tr('\\', '/'), File.read(path)]
    end
  end

  # Комментарий — проза для человека, код — поведение. Второй инвариант
  # только про поведение, поэтому строки комментариев снимаются.
  def code_only(source)
    source.lines.reject { |line| line.strip.start_with?('#') }.join
  end

  def offenders(sources, pattern, skip: nil)
    sources.filter_map do |path, source|
      next if path == skip

      matches = source.scan(pattern).uniq
      "#{path}: #{matches.join(', ')}" unless matches.empty?
    end
  end

  it 'never names the shipped provider or its domain terms, comments included' do
    found = offenders(sources, forbidden, skip: role_vocabulary)
    expect(found).to be_empty, "provider-specific words in lib/:\n#{found.join("\n")}"
  end

  it 'never branches on the name of a spec from the test corpus' do
    found = offenders(sources.transform_values { |source| code_only(source) }, corpus)
    expect(found).to be_empty, "corpus names in lib/ code:\n#{found.join("\n")}"
  end
end
