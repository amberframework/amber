require "../spec_helper"

describe Backtracer::Backtrace::Frame do
  it "#inspect" do
    with_foo_frame do |frame|
      frame.inspect.should match(/Backtrace::Frame(.*)$/)
    end
  end

  it "#to_s" do
    with_foo_frame(path: "#{__DIR__}/foo.cr") do |frame|
      frame.to_s.should eq "`foo_bar?` at #{__DIR__}/foo.cr:1:7"
    end
  end

  it "#==" do
    with_foo_frame do |frame|
      with_foo_frame do |frame2|
        frame.should eq(frame2)
      end
      with_foo_frame(method: "other_method") do |frame3|
        frame.should_not eq(frame3)
      end
    end
  end

  {% unless flag?(:release) || !flag?(:debug) %}
    describe "#context" do
      it "returns proper lines" do
        with_configuration do |configuration|
          with_backtrace(caller) do |backtrace|
            backtrace.frames.first.tap do |first_frame|
              context_lines = configuration.context_lines.should_not be_nil
              context = first_frame.context.should_not be_nil

              lines = File.read_lines(__FILE__)
              lineidx = context.lineno - 1

              context.pre
                .should eq(lines[Math.max(0, lineidx - context_lines), context_lines]?)
              context.line
                .should eq(lines[lineidx]?)
              context.post
                .should eq(lines[Math.min(lines.size, lineidx + 1), context_lines]?)
            end
          end
        end
      end

      it "returns given amount of lines" do
        with_backtrace(caller) do |backtrace|
          backtrace.frames.first.tap do |first_frame|
            context = first_frame.context(3).should_not be_nil
            context.pre.size.should eq(3)
            context.post.size.should eq(3)
          end
        end
      end
    end
  {% end %}
end
