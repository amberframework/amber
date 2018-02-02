require "../../spec_helper"

module Amber::Validators
  describe BaseRule do
    describe "#apply" do
      it "raises error when missing field" do
        params = params_builder("")
        rule = BaseRule.new("field", "") do
          false
        end

        expect_raises Exceptions::Validator::InvalidParam do
          rule.apply(params)
        end
      end

      it "returns true for given block" do
        params = params_builder("field=val")
        rule = BaseRule.new("field", "") do
          true
        end

        rule.apply(params).should be_true
      end

      it "returns false for the given block" do
        params = params_builder("field=val")
        rule = BaseRule.new("field", "") do
          false
        end

        rule.apply(params).should be_falsey
      end
    end

    describe "#error" do
      it "returns default error message" do
        params = params_builder("field=val")
        error_message = "Field field is required"
        rule = BaseRule.new("field", nil) do
          false
        end

        rule.apply(params)

        rule.error.should eq Error.new("field", "val", "Field field is required")
      end

      it "returns the given error message" do
        params = params_builder("field=val")
        error_message = "You must provide this field"
        rule = BaseRule.new("field", error_message) do
          false
        end

        rule.apply(params)

        rule.error.should eq Error.new("field", "val", error_message)
      end
    end
  end
end
