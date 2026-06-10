require "../../../spec_helper"

module Amber::Schema
  class TestSchema < Definition
  end
end

module Amber::Schema::Validator
  describe Length do
    describe "#validate" do
      context "with string values" do
        it "passes when string length is within range" do
          validator = Length.new("name", min: 3, max: 10)
          valid_strings = ["abc", "hello", "testing", "1234567890"]

          valid_strings.each do |str|
            data = {"name" => JSON::Any.new(str)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected '#{str}' (length: #{str.size}) to be valid"
          end
        end

        it "fails when string is too short" do
          validator = Length.new("name", min: 5, max: 10)
          data = {"name" => JSON::Any.new("abc")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(LengthError)
          error.field.should eq("name")
          error.details.not_nil!["min_length"].as_i.should eq(5)
          error.details.not_nil!["max_length"].as_i.should eq(10)
          error.details.not_nil!["actual_length"].as_i.should eq(3)
        end

        it "fails when string is too long" do
          validator = Length.new("name", min: 3, max: 5)
          data = {"name" => JSON::Any.new("toolong")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(LengthError)
          error.field.should eq("name")
          error.details.not_nil!["min_length"].as_i.should eq(3)
          error.details.not_nil!["max_length"].as_i.should eq(5)
          error.details.not_nil!["actual_length"].as_i.should eq(7)
        end

        it "validates with only min constraint" do
          validator = Length.new("name", min: 5)

          # Should pass
          data = {"name" => JSON::Any.new("hello world")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"name" => JSON::Any.new("hi")}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end

        it "validates with only max constraint" do
          validator = Length.new("name", max: 5)

          # Should pass
          data = {"name" => JSON::Any.new("hello")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"name" => JSON::Any.new("toolong")}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end

        it "handles empty strings" do
          validator = Length.new("name", min: 0, max: 5)
          data = {"name" => JSON::Any.new("")}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "handles unicode characters correctly" do
          validator = Length.new("name", min: 3, max: 5)
          # These are 3 characters each
          valid_strings = ["你好吗", "🎉🎊🎈", "café"]

          valid_strings.each do |str|
            data = {"name" => JSON::Any.new(str)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected '#{str}' to be valid"
          end
        end
      end

      context "with array values" do
        it "passes when array size is within range" do
          validator = Length.new("items", min: 2, max: 4)
          valid_arrays = [
            [1, 2],
            ["a", "b", "c"],
            [1, 2, 3, 4],
          ]

          valid_arrays.each do |arr|
            json_arr = arr.map { |v| JSON::Any.new(v) }
            data = {"items" => JSON::Any.new(json_arr)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected array of size #{arr.size} to be valid"
          end
        end

        it "fails when array is too small" do
          validator = Length.new("items", min: 3, max: 5)
          data = {"items" => JSON::Any.new([JSON::Any.new(1), JSON::Any.new(2)])}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(LengthError)
          error.details.not_nil!["actual_length"].as_i.should eq(2)
        end

        it "fails when array is too large" do
          validator = Length.new("items", min: 1, max: 3)
          arr = [1, 2, 3, 4, 5].map { |v| JSON::Any.new(v) }
          data = {"items" => JSON::Any.new(arr)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(LengthError)
          error.details.not_nil!["actual_length"].as_i.should eq(5)
        end

        it "handles empty arrays" do
          validator = Length.new("items", min: 0, max: 5)
          data = {"items" => JSON::Any.new([] of JSON::Any)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end

      describe "edge cases" do
        it "raises error when neither min nor max is provided" do
          expect_raises(ArgumentError, "Length validator requires at least min or max") do
            Length.new("field")
          end
        end

        it "skips validation for non-string/array types" do
          validator = Length.new("field", min: 5, max: 10)
          non_validatable_values = [
            JSON::Any.new(123_i64),
            JSON::Any.new(12.34),
            JSON::Any.new(true),
            JSON::Any.new({"key" => JSON::Any.new("value")}),
          ]

          non_validatable_values.each do |value|
            data = {"field" => value}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{value.class} to be skipped"
          end
        end

        it "skips validation when field is missing" do
          validator = Length.new("missing", min: 5)
          data = {} of String => JSON::Any
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation when field is nil" do
          validator = Length.new("field", min: 5)
          data = {"field" => JSON::Any.new(nil)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end
    end
  end

  describe MinLength do
    describe "#validate" do
      it "passes when length meets minimum" do
        validator = MinLength.new("name", 3)
        valid_values = ["abc", "hello", "very long string"]

        valid_values.each do |value|
          data = {"name" => JSON::Any.new(value)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end

      it "fails when length is below minimum" do
        validator = MinLength.new("name", 5)
        data = {"name" => JSON::Any.new("abc")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        error = result.errors.first
        error.should be_a(LengthError)
        error.details.not_nil!["min_length"].as_i.should eq(5)
        error.details.not_nil!.has_key?("max_length").should be_false
        error.details.not_nil!["actual_length"].as_i.should eq(3)
      end

      it "works with arrays" do
        validator = MinLength.new("items", 2)

        # Should pass
        data = {"items" => JSON::Any.new([JSON::Any.new(1), JSON::Any.new(2)])}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"items" => JSON::Any.new([JSON::Any.new(1)])}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end

      it "handles boundary values" do
        validator = MinLength.new("name", 5)
        data = {"name" => JSON::Any.new("12345")} # Exactly 5 characters
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
      end
    end
  end

  describe MaxLength do
    describe "#validate" do
      it "passes when length is within maximum" do
        validator = MaxLength.new("name", 10)
        valid_values = ["", "hello", "1234567890"]

        valid_values.each do |value|
          data = {"name" => JSON::Any.new(value)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end

      it "fails when length exceeds maximum" do
        validator = MaxLength.new("name", 5)
        data = {"name" => JSON::Any.new("toolong")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        error = result.errors.first
        error.should be_a(LengthError)
        error.details.not_nil!.has_key?("min_length").should be_false
        error.details.not_nil!["max_length"].as_i.should eq(5)
        error.details.not_nil!["actual_length"].as_i.should eq(7)
      end

      it "works with arrays" do
        validator = MaxLength.new("items", 3)

        # Should pass
        data = {"items" => JSON::Any.new([JSON::Any.new(1), JSON::Any.new(2)])}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        arr = [1, 2, 3, 4].map { |v| JSON::Any.new(v) }
        data = {"items" => JSON::Any.new(arr)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end

      it "handles boundary values" do
        validator = MaxLength.new("name", 5)
        data = {"name" => JSON::Any.new("12345")} # Exactly 5 characters
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
      end

      it "allows empty strings when max is 0" do
        validator = MaxLength.new("name", 0)
        data = {"name" => JSON::Any.new("")}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_true
      end
    end
  end
end
