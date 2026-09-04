# frozen_string_literal: true

require_relative 'reporter/format'
require_relative 'reporter/operation_lines'
require_relative 'reporter/schema_lines'
require_relative 'reporter/summary'

module SpecGen
  # Last pipeline stage: tells a human what was derived and what was not.
  #
  # Two outputs share this namespace. `Summary` is the screen `integrate
  # analyze` prints - one line per fact, with the derivation source and
  # confidence next to every inferred value. report.md, the file the
  # generation pipeline writes, will be built on the same profile and the
  # same formatting rules. Neither reads the spec: the profile is the only
  # input, so nothing can be shown that the generators would not also see.
  module Reporter
  end
end
