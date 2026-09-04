# frozen_string_literal: true

module SpecGen
  module Analyzers
    # A warning a reader found but cannot record.
    #
    # Readers (ParameterReader, SchemaReader, ConditionReader) are pure:
    # they take spec fragments and return IR, without touching the profile.
    # What they notice on the way travels back as Notes, and the analyzer -
    # the one object that owns the profile - turns them into warnings. One
    # place records warnings, so their order stays predictable.
    Note = Struct.new(:code, :message, :json_path, :severity, :suggested_overlay,
                      keyword_init: true)
  end
end
