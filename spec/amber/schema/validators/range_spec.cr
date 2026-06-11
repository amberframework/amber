require "../../../spec_helper"

module Amber::Schema
  class TestSchema < Definition
  end
end

module Amber::Schema::Validator
  describe Range do
    describe "#validate" do
      context "with integer values" do
        it "passes when integer is within range" do
          validator = Range.new("age", min: 18.0, max: 65.0)
          valid_ages = [18, 25, 30, 50, 65]

          valid_ages.each do |age|
            data = {"age" => JSON::Any.new(age)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{age} to be valid"
          end
        end

        it "fails when integer is below minimum" do
          validator = Range.new("age", min: 18.0, max: 65.0)
          data = {"age" => JSON::Any.new(17)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(RangeError)
          error.field.should eq("age")
          error.details.not_nil!["min"].as_f.should eq(18.0)
          error.details.not_nil!["max"].as_f.should eq(65.0)
          error.details.not_nil!["value"].as_f.should eq(17.0)
        end

        it "fails when integer is above maximum" do
          validator = Range.new("age", min: 18.0, max: 65.0)
          data = {"age" => JSON::Any.new(66)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(RangeError)
          error.details.not_nil!["value"].as_f.should eq(66.0)
        end
      end

      context "with float values" do
        it "passes when float is within range" do
          validator = Range.new("price", min: 0.0, max: 999.99)
          valid_prices = [0.0, 0.01, 50.5, 999.99]

          valid_prices.each do |price|
            data = {"price" => JSON::Any.new(price)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{price} to be valid"
          end
        end

        it "fails when float is below minimum" do
          validator = Range.new("price", min: 0.0, max: 100.0)
          data = {"price" => JSON::Any.new(-0.01)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
          error = result.errors.first
          error.should be_a(RangeError)
          error.details.not_nil!["value"].as_f.should eq(-0.01)
        end

        it "fails when float is above maximum" do
          validator = Range.new("price", min: 0.0, max: 100.0)
          data = {"price" => JSON::Any.new(100.01)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_false
        end

        it "handles precision correctly" do
          validator = Range.new("value", min: 0.1, max: 0.3)

          # Should pass
          data = {"value" => JSON::Any.new(0.2)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"value" => JSON::Any.new(0.09999)}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      describe "with only min constraint" do
        it "validates minimum boundary only" do
          validator = Range.new("score", min: 0.0)

          # Should pass
          [0, 1, 100, 999999].each do |score|
            data = {"score" => JSON::Any.new(score)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)
            validator.validate(context)
            result.success.should be_true
          end

          # Should fail
          data = {"score" => JSON::Any.new(-1)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      describe "with only max constraint" do
        it "validates maximum boundary only" do
          validator = Range.new("discount", max: 100.0)

          # Should pass
          [-100, 0, 50, 100].each do |discount|
            data = {"discount" => JSON::Any.new(discount)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)
            validator.validate(context)
            result.success.should be_true
          end

          # Should fail
          data = {"discount" => JSON::Any.new(101)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end
      end

      describe "edge cases" do
        it "raises error when neither min nor max is provided" do
          expect_raises(ArgumentError, "Range validator requires at least min or max") do
            Range.new("field")
          end
        end

        it "handles boundary values inclusively" do
          validator = Range.new("value", min: 10.0, max: 20.0)

          # Both boundaries should be valid
          [10, 20].each do |value|
            data = {"value" => JSON::Any.new(value)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)
            validator.validate(context)
            result.success.should be_true
          end
        end

        it "handles negative ranges" do
          validator = Range.new("temperature", min: -50.0, max: -10.0)

          # Should pass
          data = {"temperature" => JSON::Any.new(-30)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_true

          # Should fail
          data = {"temperature" => JSON::Any.new(-5)}
          result = LegacyResult.new(true, data)
          context = Context.new(data, result, schema)
          validator.validate(context)
          result.success.should be_false
        end

        it "handles zero values" do
          validator = Range.new("balance", min: -100.0, max: 100.0)
          data = {"balance" => JSON::Any.new(0)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation for non-numeric types" do
          validator = Range.new("field", min: 0.0, max: 100.0)
          non_numeric_values = [
            JSON::Any.new("string"),
            JSON::Any.new(true),
            JSON::Any.new(false),
            JSON::Any.new([JSON::Any.new("array")]),
            JSON::Any.new({"key" => JSON::Any.new("value")}),
          ]

          non_numeric_values.each do |value|
            data = {"field" => value}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{value.class} to be skipped"
          end
        end

        it "skips validation when field is missing" do
          validator = Range.new("missing", min: 0.0)
          data = {} of String => JSON::Any
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation when field is nil" do
          validator = Range.new("field", min: 0.0)
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

  describe Min do
    describe "#validate" do
      it "passes when value meets minimum" do
        validator = Min.new("age", 18.0)
        valid_values = [18, 19, 25, 100]

        valid_values.each do |value|
          data = {"age" => JSON::Any.new(value)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end

      it "fails when value is below minimum" do
        validator = Min.new("age", 18.0)
        data = {"age" => JSON::Any.new(17)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        error = result.errors.first
        error.should be_a(RangeError)
        error.details.not_nil!["min"].as_f.should eq(18.0)
        error.details.not_nil!.has_key?("max").should be_false
        error.details.not_nil!["value"].as_f.should eq(17.0)
      end

      it "works with floats" do
        validator = Min.new("price", 0.01)

        # Should pass
        data = {"price" => JSON::Any.new(0.01)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"price" => JSON::Any.new(0.0)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end

      it "handles negative minimum values" do
        validator = Min.new("temperature", -273.15) # Absolute zero

        # Should pass
        data = {"temperature" => JSON::Any.new(-100)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"temperature" => JSON::Any.new(-300)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end
    end
  end

  describe Max do
    describe "#validate" do
      it "passes when value is within maximum" do
        validator = Max.new("score", 100.0)
        valid_values = [-100, 0, 50, 100]

        valid_values.each do |value|
          data = {"score" => JSON::Any.new(value)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end

      it "fails when value exceeds maximum" do
        validator = Max.new("score", 100.0)
        data = {"score" => JSON::Any.new(101)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)

        validator.validate(context)

        result.success.should be_false
        error = result.errors.first
        error.should be_a(RangeError)
        error.details.not_nil!.has_key?("min").should be_false
        error.details.not_nil!["max"].as_f.should eq(100.0)
        error.details.not_nil!["value"].as_f.should eq(101.0)
      end

      it "works with floats" do
        validator = Max.new("percentage", 100.0)

        # Should pass
        data = {"percentage" => JSON::Any.new(99.99)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"percentage" => JSON::Any.new(100.01)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end

      it "handles zero as maximum" do
        validator = Max.new("debt", 0.0)

        # Should pass
        data = {"debt" => JSON::Any.new(-100)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"debt" => JSON::Any.new(1)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end

      it "handles negative maximum values" do
        validator = Max.new("loss", -10.0)

        # Should pass
        data = {"loss" => JSON::Any.new(-20)}
        result = LegacyResult.new(true, data)
        schema = TestSchema.new(data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_true

        # Should fail
        data = {"loss" => JSON::Any.new(-5)}
        result = LegacyResult.new(true, data)
        context = Context.new(data, result, schema)
        validator.validate(context)
        result.success.should be_false
      end
    end
  end
end
