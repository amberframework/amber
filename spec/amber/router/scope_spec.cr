require "../../../spec_helper"

module Amber
  module Router
    describe Scope do
      describe "#push" do
        it "register a scope" do
          scope = Scope.new

          stack = scope.push "foo"
          stack.should eq(["foo"])

          stack = scope.push "bar"
          stack.should eq(["foo", "bar"])
        end
      end

      describe "#pop" do
        it "throw exception on empty stack" do
          scope = Scope.new

          expect_raises(IndexError) { scope.pop }
        end

        it "remove one scope level" do
          scope = Scope.new
          scope.push "foo"

          scope.pop.should eq("foo")
        end
      end

      describe "#to_s" do
        it "return empty string on empty scope" do
          Scope.new.to_s.should eq("")
        end

        it "return scope with one element" do
          scope = Scope.new
          scope.push("/foo")

          scope.to_s.should eq("/foo")
        end

        it "return scope with multiples elements" do
          scope = Scope.new
          scope.push("/foo")
          scope.push("/bar")

          scope.to_s.should eq("/foo/bar")
        end
      end
    end
  end
end
