require "../src/amber"

# Example showing the new Result type system for schema validation

module ResultExample
  # Define a schema for user registration
  class UserRegistrationSchema < Amber::Schema::Definition
    field :username, String, required: true, min_length: 3, max_length: 20
    field :email, String, required: true, format: "email"
    field :password, String, required: true, min_length: 8
    field :age, Int32, min: 13, max: 120
    field :terms_accepted, Bool, required: true
  end

  # Define a typed request object
  class UserRegistrationRequest < Amber::Schema::ValidatedRequest
    def self.schema_class : Amber::Schema::Definition.class
      UserRegistrationSchema
    end

    def username : String
      @validated_data["username"].as_s
    end

    def email : String
      @validated_data["email"].as_s
    end

    def password : String
      @validated_data["password"].as_s
    end

    def age : Int32?
      @validated_data["age"]?.try(&.as_i)
    end

    def terms_accepted? : Bool
      @validated_data["terms_accepted"].as_bool
    end
  end

  def self.run
    puts "=== Result Type System Example ==="
    puts

    # Example 1: Valid registration
    puts "1. Valid registration:"
    valid_data = {
      "username"       => JSON::Any.new("johndoe"),
      "email"          => JSON::Any.new("john@example.com"),
      "password"       => JSON::Any.new("SecurePass123"),
      "age"            => JSON::Any.new(25),
      "terms_accepted" => JSON::Any.new(true),
    }

    result = UserRegistrationRequest.from_raw_data(valid_data)

    # Pattern matching approach
    case result
    when Amber::Schema::Success
      user = result.value
      puts "  ✓ Registration successful!"
      puts "  - Username: #{user.username}"
      puts "  - Email: #{user.email}"
      puts "  - Age: #{user.age || "not provided"}"
      puts "  - Terms accepted: #{user.terms_accepted?}"
    when Amber::Schema::Failure
      puts "  ✗ Registration failed:"
      result.error.errors.each do |error|
        puts "    - #{error.field}: #{error.message}"
      end
    end

    puts

    # Example 2: Invalid registration
    puts "2. Invalid registration:"
    invalid_data = {
      "username"       => JSON::Any.new("jo"), # too short
      "email"          => JSON::Any.new("not-an-email"),
      "password"       => JSON::Any.new("weak"), # too short
      "age"            => JSON::Any.new(10),     # too young
      "terms_accepted" => JSON::Any.new(false),
    }

    result = UserRegistrationRequest.from_raw_data(invalid_data)

    # Functional approach with callbacks
    result
      .on_success do |user|
        puts "  ✓ Registration successful for #{user.username}"
      end
      .on_failure do |error|
        puts "  ✗ Registration failed with #{error.errors.size} errors:"
        error.errors_by_field.each do |field, errors|
          puts "    #{field}:"
          errors.each do |e|
            puts "      - #{e.message}"
          end
        end
      end

    puts

    # Example 3: Using the typed validation directly
    puts "3. Direct schema validation with typed result:"
    schema = UserRegistrationSchema.new(valid_data)
    typed_result = schema.validate_typed

    case typed_result
    when Amber::Schema::Success
      puts "  ✓ Data is valid: #{typed_result.value.keys.join(", ")}"
    when Amber::Schema::Failure
      puts "  ✗ Validation failed"
    end

    puts

    # Example 4: Working with multiple results
    puts "4. Combining multiple validations:"

    users_data = [
      {"username" => JSON::Any.new("alice"), "email" => JSON::Any.new("alice@example.com"),
       "password" => JSON::Any.new("AlicePass123"), "terms_accepted" => JSON::Any.new(true)},
      {"username" => JSON::Any.new("bob"), "email" => JSON::Any.new("invalid-email"),
       "password" => JSON::Any.new("BobPass123"), "terms_accepted" => JSON::Any.new(true)},
      {"username" => JSON::Any.new("charlie"), "email" => JSON::Any.new("charlie@example.com"),
       "password" => JSON::Any.new("CharliePass123"), "terms_accepted" => JSON::Any.new(true)},
    ]

    results = users_data.map { |data| UserRegistrationRequest.from_raw_data(data) }

    # Count successes and failures
    successes = results.count(&.success?)
    failures = results.count(&.failure?)

    puts "  - Total registrations: #{results.size}"
    puts "  - Successful: #{successes}"
    puts "  - Failed: #{failures}"

    # Extract only successful registrations
    valid_users = results.compact_map do |result|
      result.is_a?(Amber::Schema::Success) ? result.value : nil
    end

    puts "  - Valid users: #{valid_users.map(&.username).join(", ")}"

    puts

    # Example 5: Error recovery
    puts "5. Error recovery with or_else:"

    bad_data = {"username" => JSON::Any.new("x")} # Missing required fields

    result = UserRegistrationRequest.from_raw_data(bad_data)
      .or_else do |error|
        # Try to create a guest user instead
        guest_data = {
          "username"       => JSON::Any.new("guest_#{Time.utc.to_unix}"),
          "email"          => JSON::Any.new("guest@example.com"),
          "password"       => JSON::Any.new("TempPass123"),
          "terms_accepted" => JSON::Any.new(true),
        }
        UserRegistrationRequest.from_raw_data(guest_data)
      end

    case result
    when Amber::Schema::Success
      puts "  ✓ Created guest user: #{result.value.username}"
    when Amber::Schema::Failure
      puts "  ✗ Failed to create even a guest user"
    end
  end
end

# Run the example
ResultExample.run
