require "../spec_helper"

describe Backtracer::Backtrace::Parser do
  describe ".parse" do
    it "handles `caller` as an input" do
      with_backtrace(caller) do |backtrace|
        backtrace.frames.should_not be_empty
      end
    end

    it "handles `Exception#backtrace` as an input" do
      begin
        raise "Oh, no!"
      rescue ex
        with_backtrace(ex.backtrace) do |backtrace|
          backtrace.frames.should_not be_empty
        end
      end
    end
  end
end
