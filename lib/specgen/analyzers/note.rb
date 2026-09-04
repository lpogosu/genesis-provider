# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Предупреждение, которое читатель нашёл, но записать не может.
    #
    # Читатели (ParameterReader, SchemaReader, ConditionReader) чистые: они
    # получают фрагменты спецификации и возвращают IR, не касаясь профиля.
    # Замеченное по пути возвращается обратно как Note, а анализатор —
    # единственный объект, который владеет профилем, — превращает их в
    # предупреждения. Записывает предупреждения одно место, поэтому их
    # порядок остаётся предсказуемым.
    Note = Struct.new(:code, :message, :json_path, :severity, :suggested_overlay,
                      keyword_init: true)
  end
end
