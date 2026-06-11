require "../../spec_helper"

def with_foo_context(&)
  yield Backtracer::Backtrace::Frame::Context.new(
    lineno: 10,
    pre: %w[foo bar baz],
    line: "violent offender!",
    post: %w[boo far faz],
  )
end

describe Backtracer::Backtrace::Frame::Context do
  describe ".to_a" do
    it "works with empty #pre and #post" do
      context = Backtracer::Backtrace::Frame::Context.new(
        lineno: 1,
        pre: %w[],
        line: "violent offender!",
        post: %w[],
      )
      context.to_a.should eq(["violent offender!"])
    end

    it "returns array with #pre, #line and #post strings" do
      with_foo_context do |context|
        context.to_a.should eq([
          "foo", "bar", "baz",
          "violent offender!",
          "boo", "far", "faz",
        ])
      end
    end
  end

  describe ".to_h" do
    it "works with empty #pre and #post" do
      context = Backtracer::Backtrace::Frame::Context.new(
        lineno: 1,
        pre: %w[],
        line: "violent offender!",
        post: %w[],
      )
      context.to_h.should eq({1 => "violent offender!"})
    end

    it "returns hash with #pre, #line and #post strings" do
      with_foo_context do |context|
        context.to_h.should eq({
           7 => "foo",
           8 => "bar",
           9 => "baz",
          10 => "violent offender!",
          11 => "boo",
          12 => "far",
          13 => "faz",
        })
      end
    end
  end
end
