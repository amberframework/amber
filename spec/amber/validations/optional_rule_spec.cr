require "../../spec_helper"

module Amber::Validators
  describe OptionalRule do
    describe "#apply" do
      it "does not apply rule when field is missing" do
        params = params_builder("")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          true
        end

        rule.apply(params).should be_true
        rule.value.should be_nil
      end

      it "applies rule when field is present" do
        params = params_builder("field=val")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          true
        end

        rule.apply(params).should be_true
        rule.value.should eq "val"
      end

      it "allows an empty value" do
        params = params_builder("field=")
        error_message = "You must provide this field"
        rule = OptionalRule.new("field", error_message) do
          true
        end

        rule.apply(params).should be_true
        rule.value.should eq ""
      end
    end
  end
end
