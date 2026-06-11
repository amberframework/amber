require "../../spec_helper"

describe Backtracer::Backtrace::Frame::Parser do
  describe ".parse" do
    it "fails to parse an empty string" do
      expect_raises(ArgumentError) { with_frame("", &.itself) }
    end

    context "when --no-debug flag is set" do
      it "parses frame with any value as method" do
        backtrace_line = "__crystal_main"

        with_frame(backtrace_line) do |frame|
          frame.lineno.should be_nil
          frame.column.should be_nil
          frame.method.should eq(backtrace_line)
          frame.path.should be_nil
          frame.relative_path.should be_nil
          frame.under_src_path?.should be_false
          frame.shard_name.should be_nil
          frame.in_app?.should be_false
        end
      end
    end

    context "with ~proc signature" do
      it "parses absolute path outside of src/ dir" do
        path = "/usr/local/Cellar/crystal/0.27.2/src/fiber.cr"
        backtrace_line = "~proc2Proc(Fiber, (IO::FileDescriptor | Nil))@#{path}:72"

        with_frame(backtrace_line) do |frame|
          frame.lineno.should eq(72)
          frame.column.should be_nil
          frame.method.should eq("~proc2Proc(Fiber, (IO::FileDescriptor | Nil))")
          frame.path.should eq(path)
          frame.absolute_path.should eq(frame.path)
          frame.relative_path.should be_nil
          frame.under_src_path?.should be_false
          frame.shard_name.should be_nil
          frame.in_app?.should be_false
        end
      end

      it "parses relative path inside of lib/ dir" do
        with_configuration do |configuration|
          path = "lib/kemal/src/kemal/route.cr"
          backtrace_line = "~procProc(HTTP::Server::Context, String)@#{path}:11"

          with_frame(backtrace_line) do |frame|
            frame.lineno.should eq(11)
            frame.column.should be_nil
            frame.method.should eq("~procProc(HTTP::Server::Context, String)")
            frame.path.should eq(path)
            frame.absolute_path.should eq(
              File.join(configuration.src_path.not_nil!, path)
            )
            frame.relative_path.should eq(frame.path)
            frame.under_src_path?.should be_false
            frame.shard_name.should eq("kemal")
            frame.in_app?.should be_false
          end
        end
      end
    end

    it "parses absolute path outside of configuration.src_path" do
      path = "/some/absolute/path/to/foo.cr"

      with_foo_frame(path: path) do |frame|
        frame.lineno.should eq(1)
        frame.column.should eq(7)
        frame.method.should eq("foo_bar?")
        frame.path.should eq(path)
        frame.absolute_path.should eq(frame.path)
        frame.relative_path.should be_nil
        frame.under_src_path?.should be_false
        frame.shard_name.should be_nil
        frame.in_app?.should be_false
      end
    end

    context "with in_app? = false" do
      it "parses absolute path outside of src/ dir" do
        with_foo_frame(path: "#{__DIR__}/foo.cr") do |frame|
          frame.lineno.should eq(1)
          frame.column.should eq(7)
          frame.method.should eq("foo_bar?")
          frame.path.should eq("#{__DIR__}/foo.cr")
          frame.absolute_path.should eq(frame.path)
          frame.relative_path.should eq("spec/amber/support/backtracer/backtrace/frame/foo.cr")
          frame.under_src_path?.should be_true
          frame.shard_name.should be_nil
          frame.in_app?.should be_false
        end
      end

      it "parses relative path outside of src/ dir" do
        with_configuration do |configuration|
          path = "some/relative/path/to/foo.cr"

          with_foo_frame(path: path) do |frame|
            frame.lineno.should eq(1)
            frame.column.should eq(7)
            frame.method.should eq("foo_bar?")
            frame.path.should eq(path)
            frame.absolute_path.should eq(
              File.join(configuration.src_path.not_nil!, path)
            )
            frame.relative_path.should eq(frame.path)
            frame.under_src_path?.should be_false
            frame.shard_name.should be_nil
            frame.in_app?.should be_false
          end
        end
      end
    end

    context "with in_app? = true" do
      it "parses absolute path inside of src/ dir" do
        src_path = File.expand_path("../../../../../../src", __DIR__)
        path = "#{src_path}/foo.cr"

        with_foo_frame(path: path) do |frame|
          frame.lineno.should eq(1)
          frame.column.should eq(7)
          frame.method.should eq("foo_bar?")
          frame.path.should eq(path)
          frame.absolute_path.should eq(frame.path)
          frame.relative_path.should eq("src/foo.cr")
          frame.under_src_path?.should be_true
          frame.shard_name.should be_nil
          frame.in_app?.should be_true
        end
      end

      it "parses relative path inside of src/ dir" do
        with_configuration do |configuration|
          path = "src/foo.cr"

          with_foo_frame(path: path) do |frame|
            frame.lineno.should eq(1)
            frame.column.should eq(7)
            frame.method.should eq("foo_bar?")
            frame.path.should eq(path)
            frame.absolute_path.should eq(
              File.join(configuration.src_path.not_nil!, path)
            )
            frame.relative_path.should eq(path)
            frame.under_src_path?.should be_false
            frame.shard_name.should be_nil
            frame.in_app?.should be_true
          end
        end
      end
    end

    context "with shard path" do
      it "parses absolute path inside of lib/ dir" do
        lib_path = File.expand_path("../../../../../../lib/bar", __DIR__)
        path = "#{lib_path}/src/bar.cr"

        with_foo_frame(path: path) do |frame|
          frame.lineno.should eq(1)
          frame.column.should eq(7)
          frame.method.should eq("foo_bar?")
          frame.path.should eq(path)
          frame.absolute_path.should eq(frame.path)
          frame.relative_path.should eq("lib/bar/src/bar.cr")
          frame.under_src_path?.should be_true
          frame.shard_name.should eq "bar"
          frame.in_app?.should be_false
        end
      end

      it "parses relative path inside of lib/ dir" do
        with_configuration do |configuration|
          path = "lib/bar/src/bar.cr"

          with_foo_frame(path: path) do |frame|
            frame.lineno.should eq(1)
            frame.column.should eq(7)
            frame.method.should eq("foo_bar?")
            frame.path.should eq(path)
            frame.absolute_path.should eq(
              File.join(configuration.src_path.not_nil!, path)
            )
            frame.relative_path.should eq(path)
            frame.under_src_path?.should be_false
            frame.shard_name.should eq "bar"
            frame.in_app?.should be_false
          end
        end
      end

      it "uses only folders for shard names" do
        with_foo_frame(path: "lib/bar.cr") do |frame|
          frame.shard_name.should be_nil
        end
      end
    end
  end
end
