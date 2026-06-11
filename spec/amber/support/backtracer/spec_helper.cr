require "spec"
require "../../../../src/amber/support/backtracer/backtracer"

def with_configuration(shared = true, &)
  yield shared ? Backtracer.configuration : Backtracer::Configuration.new
end

def with_backtrace(backtrace, **options, &)
  yield Backtracer::Backtrace::Parser.parse(backtrace, **options)
end

def with_frame(method, path = nil, lineno = nil, column = nil, **options, &)
  line = String.build do |io|
    if path
      io << path
      io << ':' << lineno if lineno
      io << ':' << column if column
      io << " in '" << method << '\''
    else
      io << method
    end
  end
  yield Backtracer::Backtrace::Frame::Parser.parse(line, **options)
end

def with_foo_frame(
  method = "foo_bar?",
  path = "#{__DIR__}/foo.cr",
  lineno = 1,
  column = 7,
  **options,
  &
)
  with_frame(method, path, lineno, column, **options) do |frame|
    yield frame
  end
end
