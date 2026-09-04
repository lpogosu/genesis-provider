# frozen_string_literal: true

module SpecGen
  # Root of the error hierarchy. Every failure the generator raises on user
  # input carries the spec file and the JSONPath of the offending element when
  # they are known, so the CLI can print "file at $.path: message" instead of
  # a stack trace. Nothing in lib/ raises a bare String.
  class Error < StandardError
    # @return [String, nil] spec file the error refers to
    attr_reader :file
    # @return [String, nil] location inside the file: a JSONPath such as
    #   "$.paths", or "line 5, column 3" for syntax errors
    attr_reader :path
    # @return [String, nil] the message without the location prefix
    attr_reader :detail

    # @param message [String, nil] human-readable description
    # @param file [String, nil] spec file the error refers to
    # @param path [String, nil] JSONPath (or line/column) inside that file
    def initialize(message = nil, file: nil, path: nil)
      @file = file
      @path = path
      @detail = message
      super(message)
    end

    # @return [String] message prefixed with the location when one is known
    def to_s
      base = super
      return base if location.empty?

      "#{location}: #{base}"
    end

    # @return [String] "file at $.path"; either half may be absent
    def location
      [file, path && "at #{path}"].compact.join(' ')
    end
  end

  # Loading stage: file missing or unreadable, malformed YAML or JSON, a
  # document that is not OpenAPI at all, or an unsupported OpenAPI version.
  class SpecLoadError < Error; end

  # Parsing stage: the document is OpenAPI but structurally unusable, such as
  # a missing `paths`, an unresolvable or cyclic `$ref`, or an unknown type.
  class SpecParseError < Error; end

  # Dictionary stage: something is wrong with the data under rules/ — a file
  # missing or malformed, a role outside IR::Roles, a synonym claimed by two
  # roles, a currency exponent out of range, a contract role no method
  # serves. Unlike the other errors this one is never the user's fault: the
  # dictionaries are ours, so the message lists every problem found at once
  # and the run stops before a wrong synonym reaches generated code.
  class RulesError < Error; end

  # Generation stage: template rendering failed, an artifact could not be
  # written, or generated code did not pass its own syntax check.
  class GenerationError < Error; end
end
