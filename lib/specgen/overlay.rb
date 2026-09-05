# frozen_string_literal: true

module SpecGen
  # Вторая стадия конвейера: OpenAPI Overlay Specification 1.0.0 —
  # официальный формат Инициативы OpenAPI (октябрь 2024) для документа,
  # который дополняет спецификацию, не правя её файл.
  #
  # Зачем она нужна именно так. Инструмент выводит всё, что может, а там,
  # где спецификация молчит или противоречит себе, оставляет предупреждение
  # с готовым фрагментом YAML. Overlay — это обратный ход того же цикла:
  # человек собирает фрагменты в один файл, отдаёт его флагом `--overlay`, и
  # то, о чём спецификация умалчивала, становится её частью до того, как её
  # прочитает первый анализатор. Ни один анализатор про overlay не знает: они
  # видят единый вход, а происхождение значения помечает эта стадия.
  #
  # Место в конвейере (docs/IR.md, «Границы слоёв»):
  #
  #   чтение файла → определение версии → ПРИМЕНЕНИЕ OVERLAY →
  #   проверка структуры → разрешение `$ref` → анализаторы
  #
  # Overlay применяется к исходному документу, где `$ref` ещё на месте:
  # его цели адресуют спецификацию так, как она написана. Раскрой мы `$ref`
  # раньше, компонента `$.components.schemas.X` перестала бы существовать
  # как единственное место — она оказалась бы скопированной в каждое место
  # использования. Проверка структуры идёт после overlay намеренно: то, что
  # она гарантирует остальному конвейеру, обязано быть верно для документа,
  # который конвейер увидит, а не для того, который лежал на диске.
  module Overlay
    # @param data [Hash] исходный документ спецификации; меняется на месте
    # @param file [String] путь к файлу overlay
    # @return [Result] что именно применилось, что переопределено, что не нашлось
    # @raise [OverlayError] файл нельзя прочитать как OpenAPI Overlay
    def self.apply(data, file:)
      Applier.new(Document.read(file)).call(data)
    end

    # Единственный способ отказать по вине файла overlay: сообщение из
    # locales/<код>/overlay.yml, имя файла и место внутри него.
    # @param key [String] ключ под `overlay.error.`
    # @param file [String] файл overlay
    # @param path [String] JSONPath места внутри файла overlay
    # @param params [Hash] подстановки сообщения
    # @raise [OverlayError] всегда
    def self.fail!(key, file:, path:, **params)
      raise OverlayError.new(Texts.t("overlay.error.#{key}", **params), file: file, path: path)
    end
  end
end

require_relative 'overlay/target'
require_relative 'overlay/action'
require_relative 'overlay/document'
require_relative 'overlay/result'
require_relative 'overlay/merge'
require_relative 'overlay/applier'
