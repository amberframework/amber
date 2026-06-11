require "../../../spec_helper"

module Amber::Schema
  # Simple test schema for validator tests
  class TestSchema < Definition
  end
end

module Amber::Schema::Validator
  describe Required do
    describe "#validate" do
      it "passes when field exists with a non-nil value" do
        validator = Required.new("name")
        data = {"name" => JSON::Any.new("John")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      it "passes when field exists with non-empty string" do
        validator = Required.new("email")
        data = {"email" => JSON::Any.new("test@example.com")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      it "fails when field does not exist" do
        validator = Required.new("name")
        data = {} of String => JSON::Any
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        result.errors.size.should eq(1)
        error = result.errors.first
        error.should be_a(RequiredFieldError)
        error.field.should eq("name")
      end

      it "fails when field value is nil" do
        validator = Required.new("name")
        data = {"name" => JSON::Any.new(nil)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        result.errors.size.should eq(1)
        error = result.errors.first
        error.should be_a(RequiredFieldError)
        error.field.should eq("name")
      end

      it "fails when field value is empty string" do
        validator = Required.new("name")
        data = {"name" => JSON::Any.new("")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        result.errors.size.should eq(1)
        error = result.errors.first
        error.should be_a(RequiredFieldError)
        error.field.should eq("name")
      end

      it "passes for non-string values that are not nil" do
        validator = Required.new("count")
        data = {"count" => JSON::Any.new(0)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      it "passes for boolean false value" do
        validator = Required.new("active")
        data = {"active" => JSON::Any.new(false)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      it "passes for array values" do
        validator = Required.new("items")
        data = {"items" => JSON::Any.new([] of JSON::Any)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      it "passes for hash values" do
        validator = Required.new("config")
        data = {"config" => JSON::Any.new({} of String => JSON::Any)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
        result.errors.should be_empty
      end

      describe "edge cases" do
        it "handles field names with special characters" do
          validator = Required.new("user-name")
          data = {"user-name" => JSON::Any.new("test")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "preserves existing errors in the result" do
          validator = Required.new("missing_field")
          data = {} of String => JSON::Any
          result = LegacyResult.new(true, data)
          # Add an existing error
          result.add_error(RequiredFieldError.new("other_field"))
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          result.errors.size.should eq(2)
          result.errors.map(&.field).should contain("other_field")
          result.errors.map(&.field).should contain("missing_field")
        end
      end
    end
  end
end
