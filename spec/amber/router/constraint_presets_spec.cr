require "../../spec_helper"

module Amber::Router
  describe "CONSTRAINT_PRESETS" do
    describe ":numeric" do
      it "matches digits only" do
        pattern = CONSTRAINT_PRESETS[:numeric]
        ("123" =~ pattern).should be_truthy
        ("0" =~ pattern).should be_truthy
        ("abc" =~ pattern).should be_falsey
        ("12a" =~ pattern).should be_falsey
        ("" =~ pattern).should be_falsey
      end
    end

    describe ":uuid" do
      it "matches valid UUIDs" do
        pattern = CONSTRAINT_PRESETS[:uuid]
        ("550e8400-e29b-41d4-a716-446655440000" =~ pattern).should be_truthy
        ("550E8400-E29B-41D4-A716-446655440000" =~ pattern).should be_truthy
        ("not-a-uuid" =~ pattern).should be_falsey
        ("550e8400e29b41d4a716446655440000" =~ pattern).should be_falsey
      end
    end

    describe ":slug" do
      it "matches valid slugs" do
        pattern = CONSTRAINT_PRESETS[:slug]
        ("hello-world" =~ pattern).should be_truthy
        ("my-post-123" =~ pattern).should be_truthy
        ("simple" =~ pattern).should be_truthy
        ("Hello-World" =~ pattern).should be_falsey
        ("hello--world" =~ pattern).should be_falsey
        ("-hello" =~ pattern).should be_falsey
      end
    end

    describe ":alpha" do
      it "matches alphabetic characters only" do
        pattern = CONSTRAINT_PRESETS[:alpha]
        ("hello" =~ pattern).should be_truthy
        ("Hello" =~ pattern).should be_truthy
        ("hello123" =~ pattern).should be_falsey
        ("" =~ pattern).should be_falsey
      end
    end

    describe ":alnum" do
      it "matches alphanumeric characters only" do
        pattern = CONSTRAINT_PRESETS[:alnum]
        ("hello123" =~ pattern).should be_truthy
        ("ABC" =~ pattern).should be_truthy
        ("123" =~ pattern).should be_truthy
        ("hello-world" =~ pattern).should be_falsey
      end
    end

    describe ":hex" do
      it "matches hexadecimal characters only" do
        pattern = CONSTRAINT_PRESETS[:hex]
        ("deadbeef" =~ pattern).should be_truthy
        ("DEADBEEF" =~ pattern).should be_truthy
        ("0123456789abcdef" =~ pattern).should be_truthy
        ("xyz" =~ pattern).should be_falsey
      end
    end
  end
end
