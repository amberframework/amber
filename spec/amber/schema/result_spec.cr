require "../../spec_helper"

module Amber::Schema
  # Example ValidatedRequest subclass for testing
  class CreateUserRequest < ValidatedRequest
    def self.schema_class : Definition.class
      CreateUserSchema
    end

    def username : String
      @validated_data["username"].as_s
    end

    def email : String
      @validated_data["email"].as_s
    end

    def age : Int32?
      @validated_data["age"]?.try(&.as_i)
    end
  end

  # Example schema for testing
  class CreateUserSchema < Definition
    field :username, String, required: true, min_length: 3, max_length: 20
    field :email, String, required: true, format: "email"
    field :age, Int32, min: 13, max: 120
  end

  describe "Result type system" do
    describe Success do
      it "represents a successful validation" do
        data = {"name" => JSON::Any.new("John"), "age" => JSON::Any.new(30)}
        success = Success(Hash(String, JSON::Any)).new(data)

        success.success?.should be_true
        success.failure?.should be_false
        success.value.should eq(data)
        success.error.should be_nil
      end

      it "supports map operation" do
        success = Success(Int32).new(42)

        result = success.map { |n| n * 2 }

        result.should be_a(Success(Int32))
        result.value.should eq(84)
      end

      it "supports flat_map operation" do
        success = Success(Int32).new(10)

        result = success.flat_map do |n|
          if n > 0
            Success(String).new("positive: #{n}")
          else
            error = ValidationFailure.new(
              [CustomValidationError.new("number", "Must be positive")] of Error
            )
            Failure(String).new(error)
          end
        end

        result.should be_a(Success(String))
        result.value.should eq("positive: 10")
      end

      it "ignores or_else" do
        success = Success(String).new("hello")

        result = success.or_else do |error|
          Success(String).new("recovered")
        end

        result.value.should eq("hello")
      end

      it "supports pattern matching with on_success" do
        success = Success(String).new("test")
        called = false

        success.on_success do |value|
          value.should eq("test")
          called = true
        end

        called.should be_true
      end

      it "ignores on_failure callback" do
        success = Success(String).new("test")
        called = false

        success.on_failure do |error|
          called = true
        end

        called.should be_false
      end
    end

    describe Failure do
      it "represents a failed validation" do
        errors = [RequiredFieldError.new("username")] of Error
        validation_error = ValidationFailure.new(errors, {"foo" => JSON::Any.new("bar")})
        failure = Failure(String).new(validation_error)

        failure.success?.should be_false
        failure.failure?.should be_true
        failure.value.should be_nil
        failure.error.should eq(validation_error)
      end

      it "propagates failure through map" do
        errors = [CustomValidationError.new("test", "Failed")] of Error
        validation_error = ValidationFailure.new(errors)
        failure = Failure(Int32).new(validation_error)

        result = failure.map { |n| n * 2 }

        result.should be_a(Failure(Int32))
        result.error.should eq(validation_error)
      end

      it "propagates failure through flat_map" do
        errors = [CustomValidationError.new("test", "Failed")] of Error
        validation_error = ValidationFailure.new(errors)
        failure = Failure(Int32).new(validation_error)

        result = failure.flat_map do |n|
          Success(String).new("never called")
        end

        result.should be_a(Failure(String))
        result.error.should eq(validation_error)
      end

      it "supports recovery with or_else" do
        errors = [CustomValidationError.new("test", "Failed")] of Error
        validation_error = ValidationFailure.new(errors)
        failure = Failure(String).new(validation_error)

        result = failure.or_else do |error|
          Success(String).new("recovered from: #{error.messages.first}")
        end

        result.should be_a(Success(String))
        result.value.should eq("recovered from: Failed")
      end

      it "supports pattern matching with on_failure" do
        errors = [RequiredFieldError.new("email")] of Error
        validation_error = ValidationFailure.new(errors)
        failure = Failure(String).new(validation_error)
        called = false

        failure.on_failure do |error|
          error.should eq(validation_error)
          called = true
        end

        called.should be_true
      end

      it "ignores on_success callback" do
        errors = [CustomValidationError.new("test", "Failed")] of Error
        validation_error = ValidationFailure.new(errors)
        failure = Failure(String).new(validation_error)
        called = false

        failure.on_success do |value|
          called = true
        end

        called.should be_false
      end
    end

    describe ValidationFailure do
      it "stores errors and raw data" do
        errors = [
          RequiredFieldError.new("username"),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error
        raw_data = {"age" => JSON::Any.new("not a number")}
        warnings = [Warning.new("password", "Password is weak", "weak_password")]

        validation_error = ValidationFailure.new(errors, raw_data, warnings)

        validation_error.errors.should eq(errors)
        validation_error.raw_data.should eq(raw_data)
        validation_error.warnings.should eq(warnings)
      end

      it "provides error messages" do
        errors = [
          RequiredFieldError.new("username"),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error

        validation_error = ValidationFailure.new(errors)

        messages = validation_error.messages
        messages.size.should eq(2)
        messages.should contain("Field 'username' is required")
        messages.should contain("Field 'age' must be of type Int32, got String")
      end

      it "groups errors by field" do
        errors = [
          RequiredFieldError.new("username"),
          LengthError.new("username", min: 3),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error

        validation_error = ValidationFailure.new(errors)
        errors_by_field = validation_error.errors_by_field

        errors_by_field.keys.should eq(["username", "age"])
        errors_by_field["username"].size.should eq(2)
        errors_by_field["age"].size.should eq(1)
      end

      it "checks if field has errors" do
        errors = [
          RequiredFieldError.new("username"),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error

        validation_error = ValidationFailure.new(errors)

        validation_error.has_error_for_field?("username").should be_true
        validation_error.has_error_for_field?("age").should be_true
        validation_error.has_error_for_field?("email").should be_false
      end

      it "gets errors for specific field" do
        errors = [
          RequiredFieldError.new("username"),
          LengthError.new("username", min: 3),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error

        validation_error = ValidationFailure.new(errors)

        username_errors = validation_error.errors_for_field("username")
        username_errors.size.should eq(2)
        username_errors.all? { |e| e.field == "username" }.should be_true
      end

      it "converts to hash" do
        errors = [RequiredFieldError.new("username")] of Error
        raw_data = {"test" => JSON::Any.new("data")}
        warnings = [Warning.new("info", "Just info", "info")]

        validation_error = ValidationFailure.new(errors, raw_data, warnings)
        hash = validation_error.to_h

        hash["errors"].should be_a(Array(Hash(String, JSON::Any)))
        hash["warnings"].should be_a(Array(Hash(String, JSON::Any)))
        hash["raw_data"].should eq(raw_data)
      end

      it "provides human-readable string representation" do
        errors = [
          RequiredFieldError.new("username"),
          TypeMismatchError.new("age", "Int32", "String"),
        ] of Error

        validation_error = ValidationFailure.new(errors)
        str = validation_error.to_s

        str.should contain("Validation failed with 2 error(s)")
        str.should contain("username: Field 'username' is required")
        str.should contain("age: Field 'age' must be of type Int32, got String")
      end
    end

    describe ValidatedRequest do
      it "creates from valid raw data" do
        data = {
          "username" => JSON::Any.new("johndoe"),
          "email"    => JSON::Any.new("john@example.com"),
          "age"      => JSON::Any.new(25),
        }

        result = CreateUserRequest.from_raw_data(data)

        result.should be_a(Success(CreateUserRequest))
        result.success?.should be_true

        if result.is_a?(Success)
          user_request = result.value
          user_request.username.should eq("johndoe")
          user_request.email.should eq("john@example.com")
          user_request.age.should eq(25)
        end
      end

      it "returns failure for invalid data" do
        data = {
          "username" => JSON::Any.new("jo"), # too short
          "email"    => JSON::Any.new("invalid-email"),
        }

        result = CreateUserRequest.from_raw_data(data)

        result.should be_a(Failure(CreateUserRequest))
        result.failure?.should be_true

        if result.is_a?(Failure)
          error = result.error
          error.has_error_for_field?("username").should be_true
          error.has_error_for_field?("email").should be_true
        end
      end
    end

    describe "Legacy Result compatibility" do
      it "converts to typed result for success" do
        data = {"name" => JSON::Any.new("test")}
        legacy_result = LegacyResult.success(data)

        typed_result = legacy_result.to_typed_result

        typed_result.should be_a(Success(Hash(String, JSON::Any)))
        if typed_result.is_a?(Success)
          typed_result.value.should eq(data)
        end
      end

      it "converts to typed result for failure" do
        errors = [RequiredFieldError.new("name")] of Error
        raw_data = {"foo" => JSON::Any.new("bar")}
        legacy_result = LegacyResult.failure(errors, raw_data)

        typed_result = legacy_result.to_typed_result

        typed_result.should be_a(Failure(Hash(String, JSON::Any)))
        if typed_result.is_a?(Failure)
          error = typed_result.error
          error.errors.should eq(errors)
          error.raw_data.should eq(raw_data)
        end
      end
    end

    describe ResultHelpers do
      it "returns first success from array" do
        error1 = ValidationFailure.new([CustomValidationError.new("test", "Failed 1")] of Error)
        error2 = ValidationFailure.new([CustomValidationError.new("test", "Failed 2")] of Error)

        results = [
          Failure(String).new(error1),
          Failure(String).new(error2),
          Success(String).new("success!"),
          Success(String).new("also success"),
        ]

        result = ResultHelpers.first_success(results)

        result.should be_a(Success(String))
        if result.is_a?(Success)
          result.value.should eq("success!")
        end
      end

      it "returns last failure if all failed" do
        error1 = ValidationFailure.new([CustomValidationError.new("test", "Failed 1")] of Error)
        error2 = ValidationFailure.new([CustomValidationError.new("test", "Failed 2")] of Error)

        results = [
          Failure(String).new(error1),
          Failure(String).new(error2),
        ]

        result = ResultHelpers.first_success(results)

        result.should be_a(Failure(String))
        if result.is_a?(Failure)
          result.error.should eq(error2)
        end
      end

      it "combines multiple successful results" do
        results = [
          Success(Int32).new(1),
          Success(Int32).new(2),
          Success(Int32).new(3),
        ]

        result = ResultHelpers.combine(results)

        result.should be_a(Success(Array(Int32)))
        if result.is_a?(Success)
          result.value.should eq([1, 2, 3])
        end
      end

      it "combines failures and successes into failure" do
        results = [
          Success(String).new("ok"),
          Failure(String).new(ValidationFailure.new([RequiredFieldError.new("field1")] of Error)),
          Failure(String).new(ValidationFailure.new([RequiredFieldError.new("field2")] of Error)),
        ]

        result = ResultHelpers.combine(results)

        result.should be_a(Failure(Array(String)))
        if result.is_a?(Failure)
          error = result.error
          error.errors.size.should eq(2)
          error.messages.should contain("Field 'field1' is required")
          error.messages.should contain("Field 'field2' is required")
        end
      end

      it "sequences hash of successful results" do
        results = {
          "a" => Success(Int32).new(1),
          "b" => Success(Int32).new(2),
          "c" => Success(Int32).new(3),
        }

        result = ResultHelpers.sequence(results)

        result.should be_a(Success(Hash(String, Int32)))
        if result.is_a?(Success)
          result.value.should eq({"a" => 1, "b" => 2, "c" => 3})
        end
      end

      it "sequences hash with failures into failure" do
        results = {
          "a" => Success(String).new("ok"),
          "b" => Failure(String).new(ValidationFailure.new([RequiredFieldError.new("b")] of Error)),
          "c" => Failure(String).new(ValidationFailure.new([TypeMismatchError.new("c", "String", "Int32")] of Error)),
        }

        result = ResultHelpers.sequence(results)

        result.should be_a(Failure(Hash(String, String)))
        if result.is_a?(Failure)
          error = result.error
          error.errors.size.should eq(2)
          error.has_error_for_field?("b").should be_true
          error.has_error_for_field?("c").should be_true
        end
      end
    end

    describe "Schema integration" do
      it "validates typed result with valid data" do
        data = {
          "username" => JSON::Any.new("johndoe"),
          "email"    => JSON::Any.new("john@example.com"),
          "age"      => JSON::Any.new(25),
        }

        schema = CreateUserSchema.new(data)
        result = schema.validate_typed

        result.should be_a(Success(Hash(String, JSON::Any)))
        if result.is_a?(Success)
          result.value.should eq(data)
        end
      end

      it "validates typed result with invalid data" do
        data = {
          "username" => JSON::Any.new("jo"), # too short
          "email"    => JSON::Any.new("not-an-email"),
          "age"      => JSON::Any.new(200), # too old
        }

        schema = CreateUserSchema.new(data)
        result = schema.validate_typed

        result.should be_a(Failure(Hash(String, JSON::Any)))
        if result.is_a?(Failure)
          error = result.error
          error.has_error_for_field?("username").should be_true
          error.has_error_for_field?("email").should be_true
          error.has_error_for_field?("age").should be_true
        end
      end
    end
  end
end
