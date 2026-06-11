module Backtracer
  module Backtrace::Parser
    extend self

    # Parses *backtrace* (possibly obtained as a return value
    # from `caller` or `Exception#backtrace` methods).
    #
    # Accepts options:
    # - `configuration`: `Configuration` object - uses `Backtracer.configuration` if `nil`
    # - `filters`: additional line filters - see `Configuration#line_filters`
    #
    # Returns parsed `Backtrace` object or raises `ArgumentError` otherwise.
    def parse(backtrace : Array(String), **options) : Backtrace
      configuration = options[:configuration]? || Backtracer.configuration

      filters = configuration.line_filters
      if extra_filters = options[:filters]?
        filters += extra_filters
      end

      lines = backtrace.compact_map do |line|
        filters.reduce(line) do |nested_line, filter|
          filter.call(nested_line) || break
        end
      end

      frames = lines.map do |line|
        Frame::Parser.parse(line, configuration: configuration)
      end

      Backtrace.new(frames)
    end

    def parse(backtrace : String, **options) : Backtrace
      parse(backtrace.lines, **options)
    end
  end
end
