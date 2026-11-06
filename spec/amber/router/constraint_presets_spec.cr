require "../../spec_helper"

module Amber::Router
  describe "CONSTRAINT_PRESETS" do
    describe ":numeric" do
      it "matches digits only" do
        pattern = CONSTRAINT_PRESETS[:numeric]
        pattern.matches?("123").should be_true
        pattern.matches?("0").should be_true
        pattern.matches?("abc").should be_false
        pattern.matches?("12a").should be_false
        pattern.matches?("").should be_false
      end
    end

    describe ":uuid" do
      it "matches valid UUIDs" do
        pattern = CONSTRAINT_PRESETS[:uuid]
        pattern.matches?("550e8400-e29b-41d4-a716-446655440000").should be_true
        pattern.matches?("550E8400-E29B-41D4-A716-446655440000").should be_true
        pattern.matches?("not-a-uuid").should be_false
        pattern.matches?("550e8400e29b41d4a716446655440000").should be_false
      end
    end

    describe ":slug" do
      it "matches valid slugs" do
        pattern = CONSTRAINT_PRESETS[:slug]
        pattern.matches?("hello-world").should be_true
        pattern.matches?("my-post-123").should be_true
        pattern.matches?("simple").should be_true
        pattern.matches?("Hello-World").should be_false
        pattern.matches?("hello--world").should be_false
        pattern.matches?("-hello").should be_false
      end
    end

    describe ":alpha" do
      it "matches alphabetic characters only" do
        pattern = CONSTRAINT_PRESETS[:alpha]
        pattern.matches?("hello").should be_true
        pattern.matches?("Hello").should be_true
        pattern.matches?("hello123").should be_false
        pattern.matches?("").should be_false
      end
    end

    describe ":alnum" do
      it "matches alphanumeric characters only" do
        pattern = CONSTRAINT_PRESETS[:alnum]
        pattern.matches?("hello123").should be_true
        pattern.matches?("ABC").should be_true
        pattern.matches?("123").should be_true
        pattern.matches?("hello-world").should be_false
      end
    end

    describe ":hex" do
      it "matches hexadecimal characters only" do
        pattern = CONSTRAINT_PRESETS[:hex]
        pattern.matches?("deadbeef").should be_true
        pattern.matches?("DEADBEEF").should be_true
        pattern.matches?("0123456789abcdef").should be_true
        pattern.matches?("xyz").should be_false
      end
    end
  end
end
