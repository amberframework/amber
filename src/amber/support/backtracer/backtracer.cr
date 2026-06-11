module Backtracer
  class_getter(configuration) { Configuration.new }

  def self.configure(&) : Nil
    yield configuration
  end

  def self.parse(backtrace : Array(String) | String, **options) : Backtrace
    Backtrace::Parser.parse(backtrace, **options)
  end
end

require "./backtrace"
require "./configuration"
require "./backtrace/**"
