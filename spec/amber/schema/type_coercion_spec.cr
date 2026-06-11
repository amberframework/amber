require "../../spec_helper"

module Amber::Schema
  describe TypeCoercion do
    describe ".coerce" do
      context "String coercion" do
        it "keeps strings as-is" do
          value = JSON::Any.new("hello")
          result = TypeCoercion.coerce(value, "String")
          result.should_not be_nil
          result.not_nil!.as_s.should eq "hello"
        end

        it "converts numbers to strings" do
          value = JSON::Any.new(123)
          result = TypeCoercion.coerce(value, "String")
          result.should_not be_nil
          result.not_nil!.as_s.should eq "123"
        end

        it "converts booleans to strings" do
          value = JSON::Any.new(true)
          result = TypeCoercion.coerce(value, "String")
          result.should_not be_nil
          result.not_nil!.as_s.should eq "true"
        end
      end

      context "Int32 coercion" do
        it "keeps Int32 as-is" do
          value = JSON::Any.new(42)
          result = TypeCoercion.coerce(value, "Int32")
          result.should_not be_nil
          result.not_nil!.as_i.should eq 42
        end

        it "converts Int64 to Int32 if in range" do
          value = JSON::Any.new(42_i64)
          result = TypeCoercion.coerce(value, "Int32")
          result.should_not be_nil
          result.not_nil!.as_i.should eq 42
        end

        it "returns nil for Int64 out of Int32 range" do
          value = JSON::Any.new(Int64::MAX)
          result = TypeCoercion.coerce(value, "Int32")
          result.should be_nil
        end

        it "converts string to Int32" do
          value = JSON::Any.new("123")
          result = TypeCoercion.coerce(value, "Int32")
          result.should_not be_nil
          result.not_nil!.as_i.should eq 123
        end

        it "converts exact float to Int32" do
          value = JSON::Any.new(42.0)
          result = TypeCoercion.coerce(value, "Int32")
          result.should_not be_nil
          result.not_nil!.as_i.should eq 42
        end

        it "returns nil for non-exact float" do
          value = JSON::Any.new(42.5)
          result = TypeCoercion.coerce(value, "Int32")
          result.should be_nil
        end

        it "returns nil for invalid string" do
          value = JSON::Any.new("not a number")
          result = TypeCoercion.coerce(value, "Int32")
          result.should be_nil
        end

        it "returns nil for empty string" do
          value = JSON::Any.new("")
          result = TypeCoercion.coerce(value, "Int32")
          result.should be_nil
        end
      end

      context "Bool coercion" do
        it "keeps booleans as-is" do
          value = JSON::Any.new(true)
          result = TypeCoercion.coerce(value, "Bool")
          result.should_not be_nil
          result.not_nil!.as_bool.should be_true
        end

        it "converts 'true' string variations" do
          ["true", "TRUE", "True", "1", "yes", "YES", "y", "on", "t", "enabled", "active"].each do |str|
            value = JSON::Any.new(str)
            result = TypeCoercion.coerce(value, "Bool")
            result.should_not be_nil
            result.not_nil!.as_bool.should be_true
          end
        end

        it "converts 'false' string variations" do
          ["false", "FALSE", "False", "0", "no", "NO", "n", "off", "f", "disabled", "inactive"].each do |str|
            value = JSON::Any.new(str)
            result = TypeCoercion.coerce(value, "Bool")
            result.should_not be_nil
            result.not_nil!.as_bool.should be_false
          end
        end

        it "converts integer 1 to true" do
          value = JSON::Any.new(1)
          result = TypeCoercion.coerce(value, "Bool")
          result.should_not be_nil
          result.not_nil!.as_bool.should be_true
        end

        it "converts integer 0 to false" do
          value = JSON::Any.new(0)
          result = TypeCoercion.coerce(value, "Bool")
          result.should_not be_nil
          result.not_nil!.as_bool.should be_false
        end

        it "returns nil for other integers" do
          value = JSON::Any.new(42)
          result = TypeCoercion.coerce(value, "Bool")
          result.should be_nil
        end

        it "handles string with spaces" do
          value = JSON::Any.new("  true  ")
          result = TypeCoercion.coerce(value, "Bool")
          result.should_not be_nil
          result.not_nil!.as_bool.should be_true
        end
      end

      context "Time coercion" do
        it "parses ISO8601 format" do
          value = JSON::Any.new("2023-12-25T10:30:00Z")
          result = TypeCoercion.coerce(value, "Time")
          result.should_not be_nil
          # Result should be a valid ISO8601 string
          result.not_nil!.as_s.should match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end

        it "parses various date formats" do
          dates = [
            "2023-12-25",
            "25-12-2023",
            "12-25-2023",
            "25/12/2023",
            "12/25/2023",
            "2023-12-25 10:30:00",
            "2023/12/25 10:30:00",
          ]

          dates.each do |date_str|
            value = JSON::Any.new(date_str)
            result = TypeCoercion.coerce(value, "Time")
            result.should_not be_nil
          end
        end

        it "converts Unix timestamp" do
          timestamp = 1703502600_i64 # 2023-12-25 10:30:00 UTC
          value = JSON::Any.new(timestamp)
          result = TypeCoercion.coerce(value, "Time")
          result.should_not be_nil
          result.not_nil!.as_s.should match(/2023-12-25/)
        end

        it "returns nil for invalid time string" do
          value = JSON::Any.new("not a time")
          result = TypeCoercion.coerce(value, "Time")
          result.should be_nil
        end
      end

      context "UUID coercion" do
        it "validates and returns valid UUID" do
          uuid_str = "550e8400-e29b-41d4-a716-446655440000"
          value = JSON::Any.new(uuid_str)
          result = TypeCoercion.coerce(value, "UUID")
          result.should_not be_nil
          result.not_nil!.as_s.should eq uuid_str
        end

        it "returns nil for invalid UUID" do
          value = JSON::Any.new("not-a-uuid")
          result = TypeCoercion.coerce(value, "UUID")
          result.should be_nil
        end

        it "returns nil for empty string" do
          value = JSON::Any.new("")
          result = TypeCoercion.coerce(value, "UUID")
          result.should be_nil
        end
      end

      context "Array coercion" do
        it "keeps arrays and coerces elements" do
          value = JSON::Any.new([JSON::Any.new("1"), JSON::Any.new("2"), JSON::Any.new("3")])
          result = TypeCoercion.coerce(value, "Array(Int32)")
          result.should_not be_nil
          array = result.not_nil!.as_a
          array.size.should eq 3
          array[0].as_i.should eq 1
          array[1].as_i.should eq 2
          array[2].as_i.should eq 3
        end

        it "parses JSON array string" do
          value = JSON::Any.new("[1, 2, 3]")
          result = TypeCoercion.coerce(value, "Array(Int32)")
          result.should_not be_nil
          array = result.not_nil!.as_a
          array.size.should eq 3
        end

        it "parses comma-separated values for simple types" do
          value = JSON::Any.new("1,2,3")
          result = TypeCoercion.coerce(value, "Array(Int32)")
          result.should_not be_nil
          array = result.not_nil!.as_a
          array.size.should eq 3
          array[0].as_i.should eq 1
        end

        it "wraps single value in array" do
          value = JSON::Any.new("42")
          result = TypeCoercion.coerce(value, "Array(Int32)")
          result.should_not be_nil
          array = result.not_nil!.as_a
          array.size.should eq 1
          array[0].as_i.should eq 42
        end

        it "skips elements that can't be coerced" do
          value = JSON::Any.new([JSON::Any.new("1"), JSON::Any.new("invalid"), JSON::Any.new("3")])
          result = TypeCoercion.coerce(value, "Array(Int32)")
          result.should_not be_nil
          array = result.not_nil!.as_a
          array.size.should eq 2
          array[0].as_i.should eq 1
          array[1].as_i.should eq 3
        end
      end

      context "Hash coercion" do
        it "keeps hashes and coerces values" do
          value = JSON::Any.new({"a" => JSON::Any.new("1"), "b" => JSON::Any.new("2")})
          result = TypeCoercion.coerce(value, "Hash(String, Int32)")
          result.should_not be_nil
          hash = result.not_nil!.as_h
          hash.size.should eq 2
          hash["a"].as_i.should eq 1
          hash["b"].as_i.should eq 2
        end

        it "parses JSON object string" do
          value = JSON::Any.new(%[{"a": 1, "b": 2}])
          result = TypeCoercion.coerce(value, "Hash(String, Int32)")
          result.should_not be_nil
          hash = result.not_nil!.as_h
          hash.size.should eq 2
        end

        it "skips values that can't be coerced" do
          value = JSON::Any.new({"a" => JSON::Any.new("1"), "b" => JSON::Any.new("invalid"), "c" => JSON::Any.new("3")})
          result = TypeCoercion.coerce(value, "Hash(String, Int32)")
          result.should_not be_nil
          hash = result.not_nil!.as_h
          hash.size.should eq 2
          hash.has_key?("b").should be_false
        end
      end

      context "nil handling" do
        it "returns nil for nil values" do
          value = JSON::Any.new(nil)
          TypeCoercion.coerce(value, "String").should be_nil
          TypeCoercion.coerce(value, "Int32").should be_nil
          TypeCoercion.coerce(value, "Bool").should be_nil
        end
      end
    end

    describe "custom coercion" do
      it "allows registering custom coercion functions" do
        # Register a custom type that doubles integers
        TypeCoercion.register("DoubledInt") do |value|
          if int_val = value.as_i?
            JSON::Any.new(int_val * 2)
          else
            nil
          end
        end

        value = JSON::Any.new(21)
        result = TypeCoercion.coerce(value, "DoubledInt")
        result.should_not be_nil
        result.not_nil!.as_i.should eq 42

        # Clean up
        TypeCoercion.clear_custom_coercions
      end
    end

    describe ".can_coerce?" do
      it "returns true for valid coercions" do
        TypeCoercion.can_coerce?(JSON::Any.new("123"), "Int32").should be_true
        TypeCoercion.can_coerce?(JSON::Any.new("true"), "Bool").should be_true
        TypeCoercion.can_coerce?(JSON::Any.new("2023-12-25"), "Time").should be_true
      end

      it "returns false for invalid coercions" do
        TypeCoercion.can_coerce?(JSON::Any.new("not a number"), "Int32").should be_false
        TypeCoercion.can_coerce?(JSON::Any.new("maybe"), "Bool").should be_false
        TypeCoercion.can_coerce?(JSON::Any.new("not a time"), "Time").should be_false
      end
    end

    describe ".coercion_error" do
      it "provides descriptive error information" do
        value = JSON::Any.new("not a number")
        error = TypeCoercion.coercion_error("age", value, "Int32")

        error.field.should eq "age"
        error.source_type.should eq "String"
        error.target_type.should eq "Int32"
        error.value.should eq "not a number"
        error.message.should eq "Cannot coerce age from String (not a number) to Int32"
      end
    end
  end
end
