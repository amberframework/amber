module Backtracer
  module Backtrace::Frame::Parser
    extend self

    # Parses a single line of a given backtrace, where *line* is
    # the raw line from `caller` or some backtrace.
    #
    # Accepts options:
    # - `configuration`: `Configuration` object - uses `Backtracer.configuration` if `nil`
    #
    # Returns parsed `Backtrace::Frame` on success or `nil` otherwise.
    def parse?(line : String, **options) : Backtrace::Frame?
      return unless Configuration::LINE_PATTERNS.any? &.match(line)

      method = $~["method"]?.presence
      file = $~["file"]?.presence
      lineno = $~["line"]?.try(&.to_i?)
      column = $~["col"]?.try(&.to_i?)

      return unless method

      Backtrace::Frame.new method, file, lineno, column,
        configuration: options[:configuration]?
    end

    # Same as `parse?` but raises `ArgumentError` on error.
    def parse(line : String, **options) : Backtrace::Frame
      parse?(line, **options) ||
        raise ArgumentError.new("Error parsing line: #{line.inspect}")
    end
  end
end
