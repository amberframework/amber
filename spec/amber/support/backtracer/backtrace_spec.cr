require "./spec_helper"

describe Backtracer::Backtrace do
  it "#frames" do
    with_backtrace(caller) do |backtrace|
      backtrace.frames.should be_a(Array(Backtracer::Backtrace::Frame))
      backtrace.frames.should_not be_empty
    end
  end

  it "#inspect" do
    with_backtrace(caller) do |backtrace|
      backtrace.inspect.should match(/#<Backtrace: .+>$/)
    end
  end

  {% unless flag?(:release) || !flag?(:debug) %}
    it "#to_s" do
      with_backtrace(caller) do |backtrace|
        backtrace.to_s.should match(/backtrace_spec.cr/)
      end
    end
  {% end %}

  it "#==" do
    with_backtrace(caller) do |backtrace|
      backtrace2 = Backtracer::Backtrace.new(backtrace.frames)
      backtrace2.should eq(backtrace)
    end
  end
end
