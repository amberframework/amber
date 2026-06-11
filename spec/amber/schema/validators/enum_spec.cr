require "../../../spec_helper"

module Amber::Schema
  class TestSchema < Definition
  end
end

module Amber::Schema::Validator
  describe Enum do
    describe "#validate" do
      context "with string enum values" do
        it "passes when value is in allowed list" do
          validator = Enum.new("status", ["active", "inactive", "pending"])
          valid_statuses = ["active", "inactive", "pending"]

          valid_statuses.each do |status|
            data = {"status" => JSON::Any.new(status)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected '#{status}' to be valid"
          end
        end

        it "fails when value is not in allowed list" do
          validator = Enum.new("status", ["active", "inactive", "pending"])
          data = {"status" => JSON::Any.new("archived")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(CustomValidationError)
          error.field.should eq("status")
          error.message.not_nil!.should contain("must be one of: active, inactive, pending")
          error.code.should eq("invalid_enum_value")
        end

        it "is case sensitive" do
          validator = Enum.new("status", ["Active", "Inactive"])

          # Should pass
          data = {"status" => JSON::Any.new("Active")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"status" => JSON::Any.new("active")} # lowercase
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      context "with integer enum values" do
        it "passes when integer value is in allowed list" do
          validator = Enum.new("priority", [1, 2, 3])

          [1, 2, 3].each do |priority|
            data = {"priority" => JSON::Any.new(priority)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true
          end
        end

        it "fails when integer value is not in allowed list" do
          validator = Enum.new("priority", [1, 2, 3])
          data = {"priority" => JSON::Any.new(4)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.message.not_nil!.should contain("must be one of: 1, 2, 3")
        end

        it "handles string representation of integers" do
          validator = Enum.new("level", [1, 2, 3])

          # Should fail - enum expects integer but receives string
          data = {"level" => JSON::Any.new("1")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
        end
      end

      context "with float enum values" do
        it "passes when float value is in allowed list" do
          validator = Enum.new("rate", [0.5, 1.0, 1.5, 2.0])

          [0.5, 1.0, 1.5, 2.0].each do |rate|
            data = {"rate" => JSON::Any.new(rate)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true
          end
        end

        it "fails when float value is not in allowed list" do
          validator = Enum.new("rate", [0.5, 1.0, 1.5])
          data = {"rate" => JSON::Any.new(2.5)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
        end

        it "handles float precision correctly" do
          validator = Enum.new("discount", [0.1, 0.2, 0.3])

          # Should pass
          data = {"discount" => JSON::Any.new(0.2)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail - slight precision difference
          data = {"discount" => JSON::Any.new(0.20000001)}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      context "with boolean values" do
        it "can validate boolean values" do
          validator = Enum.new("enabled", ["true", "false"])

          # Should pass
          data = {"enabled" => JSON::Any.new(true)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should also pass
          data = {"enabled" => JSON::Any.new(false)}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true
        end
      end

      describe "mixed type handling" do
        it "converts all allowed values to strings for comparison" do
          validator = Enum.new("code", ["A1", "B2", "100", "200"])

          # String values
          data = {"code" => JSON::Any.new("A1")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Integer that matches string representation
          data = {"code" => JSON::Any.new(100)}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true
        end
      end

      describe "edge cases" do
        it "raises error when allowed values array is empty" do
          expect_raises(ArgumentError, "Enum validator requires at least one allowed value") do
            Enum.new("field", [] of String)
          end
        end

        it "handles single allowed value" do
          validator = Enum.new("constant", ["fixed_value"])

          # Should pass
          data = {"constant" => JSON::Any.new("fixed_value")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"constant" => JSON::Any.new("other_value")}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end

        it "skips validation when field is missing" do
          validator = Enum.new("missing", ["a", "b", "c"])
          data = {} of String => JSON::Any
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation when field is nil" do
          validator = Enum.new("field", ["a", "b", "c"])
          data = {"field" => JSON::Any.new(nil)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "handles empty string as valid enum value" do
          validator = Enum.new("option", ["", "yes", "no"])
          data = {"option" => JSON::Any.new("")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "handles whitespace in enum values" do
          validator = Enum.new("choice", ["option 1", "option 2", "option 3"])

          # Should pass
          data = {"choice" => JSON::Any.new("option 1")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail - no trimming
          data = {"choice" => JSON::Any.new("option 1 ")} # Extra space
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end

        it "preserves order in error message" do
          validator = Enum.new("size", ["small", "medium", "large", "extra-large"])
          data = {"size" => JSON::Any.new("tiny")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          error = result.errors.first
          error.message.not_nil!.should eq("Field 'size' must be one of: small, medium, large, extra-large")
        end

        it "handles special characters in enum values" do
          validator = Enum.new("symbol", ["@", "#", "$", "&"])

          ["@", "#", "$", "&"].each do |symbol|
            data = {"symbol" => JSON::Any.new(symbol)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true
          end
        end

        it "handles unicode characters in enum values" do
          validator = Enum.new("emoji", ["😀", "😎", "🎉"])

          # Should pass
          data = {"emoji" => JSON::Any.new("😀")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"emoji" => JSON::Any.new("😢")}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      describe "error message formatting" do
        it "provides clear error message for small enum sets" do
          validator = Enum.new("color", ["red", "green", "blue"])
          data = {"color" => JSON::Any.new("yellow")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          error = result.errors.first
          error.message.not_nil!.should eq("Field 'color' must be one of: red, green, blue")
        end

        it "lists all values even for large enum sets" do
          allowed = (1..10).map(&.to_s)
          validator = Enum.new("number", allowed)
          data = {"number" => JSON::Any.new("11")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          error = result.errors.first
          error.message.not_nil!.should contain("1, 2, 3, 4, 5, 6, 7, 8, 9, 10")
        end
      end
    end
  end
end
