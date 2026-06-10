# Comprehensive examples of Form Data Parser usage in Amber Schema API
#
# This file demonstrates the enhanced form data parsing capabilities including:
# - URL-encoded form parsing with nested structures
# - File upload handling with validation
# - Complex form structures with arrays and objects
# - Integration with the Schema API validation system

require "../definition"
require "../parser"
require "../errors"
require "../validator"
require "../result"

module FormDataExample
  # Example 1: Basic user registration form
  class UserRegistrationSchema < Amber::Schema::Definition
    field :first_name, String, required: true, min_length: 2, max_length: 50
    field :last_name, String, required: true, min_length: 2, max_length: 50
    field :email, String, required: true, format: "email"
    field :password, String, required: true, min_length: 8
    field :age, Int32, min: 13, max: 120
    field :terms_accepted, Bool, required: true
    field :newsletter_subscription, Bool, default: false
  end

  # Example 2: Complex profile form with nested data
  class UserProfileSchema < Amber::Schema::Definition
    # Nested user data using bracket notation
    field :user_name, String, as: "user[name]", required: true
    field :user_email, String, as: "user[email]", required: true, format: "email"
    field :user_bio, String, as: "user[bio]", max_length: 500

    # Nested address information
    field :address_street, String, as: "user[address][street]"
    field :address_city, String, as: "user[address][city]"
    field :address_state, String, as: "user[address][state]"
    field :address_zip, String, as: "user[address][zip]", pattern: "^\\d{5}(-\\d{4})?$"

    # Array fields for tags and interests
    field :tags, Array(String), repeated: true # tags[]=tag1&tags[]=tag2
    field :interests, Array(String), repeated: true

    # Skills with proficiency levels (nested arrays)
    field :skills, Array(String), repeated: true
  end

  # Example 3: File upload form with validation
  class DocumentUploadSchema < Amber::Schema::Definition
    field :title, String, required: true, min_length: 3, max_length: 100
    field :description, String, max_length: 1000
    field :category, String, required: true

    # Single file upload with comprehensive validation
    field :primary_file, Hash(String, JSON::Any),
      required: true,
      max_size: 10485760

    # Optional image thumbnail
    field :thumbnail, Hash(String, JSON::Any),
      max_size: 2097152

    # Multiple attachments
    field :attachments, Array(Hash(String, JSON::Any)),
      max_size: 5242880 # Per file limit

    # Metadata
    field :tags, Array(String), repeated: true
    field :is_public, Bool, default: false
    field :allow_downloads, Bool, default: true
  end

  # Example 4: Advanced form with conditional fields
  class OrderFormSchema < Amber::Schema::Definition
    # Basic order information
    field :product_name, String, required: true
    field :quantity, Int32, required: true, min: 1, max: 100
    field :shipping_method, String, required: true

    # Customer information
    field :customer_name, String, required: true
    field :customer_email, String, required: true, format: "email"
    field :customer_phone, String, pattern: "^\\+?[1-9]\\d{1,14}$"

    # Shipping address
    field :shipping_street, String, as: "shipping[street]", required: true
    field :shipping_city, String, as: "shipping[city]", required: true
    field :shipping_state, String, as: "shipping[state]", required: true
    field :shipping_zip, String, as: "shipping[zip]", required: true

    # Payment method selection
    field :payment_method, String, required: true

    # Gift options
    field :is_gift, Bool, default: false
    field :gift_message, String, max_length: 200
    field :gift_wrapping, String, default: "none"

    # Special instructions
    field :special_instructions, String, max_length: 500
    field :delivery_notes, String, max_length: 300
  end

  # Example 5: Multi-step form data aggregation
  class ApplicationFormSchema < Amber::Schema::Definition
    # Personal information (step 1)
    field :personal_name, String, as: "personal[name]", required: true
    field :personal_email, String, as: "personal[email]", required: true, format: "email"
    field :personal_phone, String, as: "personal[phone]", required: true
    field :personal_address, String, as: "personal[address]", required: true

    # Professional information (step 2)
    field :work_title, String, as: "work[title]", required: true
    field :work_company, String, as: "work[company]", required: true
    field :work_experience, Int32, as: "work[experience]", required: true, min: 0, max: 50
    field :work_skills, Array(String), as: "work[skills]", repeated: true

    # Documents (step 3)
    field :resume, Hash(String, JSON::Any),
      required: true,
      max_size: 5242880

    field :cover_letter, Hash(String, JSON::Any),
      max_size: 2097152

    field :portfolio_files, Array(Hash(String, JSON::Any)),
      max_size: 10485760

    # References (step 4)
    field :references, Array(String), repeated: true, min_length: 2

    # Final confirmations
    field :terms_accepted, Bool, required: true
    field :privacy_policy_accepted, Bool, required: true
    field :marketing_consent, Bool, default: false
  end

  # Demonstration methods
  def self.demonstrate_basic_form
    puts "=== Basic User Registration Example ==="

    # Simulate form submission
    form_data = "first_name=John&last_name=Doe&email=john.doe@example.com&password=secretpass123&age=28&terms_accepted=true&newsletter_subscription=false"

    request = HTTP::Request.new("POST", "/register")
    request.headers["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = IO::Memory.new(form_data)

    # Parse using the enhanced form parser
    data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
    puts "Parsed data: #{data}"

    # Validate with schema
    schema = UserRegistrationSchema.new(data)
    result = schema.validate

    if result.success?
      puts "✅ Validation successful!"
      puts "Name: #{schema.first_name} #{schema.last_name}"
      puts "Email: #{schema.email}"
      puts "Age: #{schema.age}"
      puts "Newsletter: #{schema.newsletter_subscription}"
    else
      puts "❌ Validation failed:"
      result.errors.each do |error|
        puts "  - #{error.field}: #{error.message}"
      end
    end
  end

  def self.demonstrate_nested_form
    puts "\n=== Nested Form Data Example ==="

    # Complex nested form data
    form_data = [
      "user[name]=Jane Smith",
      "user[email]=jane@example.com",
      "user[bio]=Software developer with 5 years experience",
      "user[address][street]=123 Tech Street",
      "user[address][city]=San Francisco",
      "user[address][state]=CA",
      "user[address][zip]=94105",
      "tags[]=developer",
      "tags[]=javascript",
      "tags[]=crystal",
      "interests[]=programming",
      "interests[]=hiking",
      "interests[]=photography",
      "skills[]=Crystal",
      "skills[]=JavaScript",
      "skills[]=Docker",
    ].join("&")

    request = HTTP::Request.new("POST", "/profile")
    request.headers["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = IO::Memory.new(form_data)

    data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
    puts "Parsed nested data structure:"
    puts data.to_pretty_json

    schema = UserProfileSchema.new(data)
    result = schema.validate

    if result.success?
      puts "✅ Profile validation successful!"
      puts "User: #{schema.user_name} (#{schema.user_email})"
      puts "Address: #{schema.address_street}, #{schema.address_city}, #{schema.address_state} #{schema.address_zip}"
      puts "Tags: #{schema.tags.try(&.join(", "))}"
      puts "Interests: #{schema.interests.try(&.join(", "))}"
      puts "Skills: #{schema.skills.try(&.join(", "))}"
    else
      puts "❌ Profile validation failed:"
      result.errors.each do |error|
        puts "  - #{error.field}: #{error.message}"
      end
    end
  end

  def self.demonstrate_file_validation
    puts "\n=== File Upload Validation Example ==="

    # Create mock file upload data (as would be created by multipart parser)
    file_data = {
      "filename"     => JSON::Any.new("document.pdf"),
      "content_type" => JSON::Any.new("application/pdf"),
      "size"         => JSON::Any.new(2048000_i64), # 2MB
      "content"      => JSON::Any.new("Mock PDF content"),
      "headers"      => JSON::Any.new({
        "Content-Type"        => JSON::Any.new("application/pdf"),
        "Content-Disposition" => JSON::Any.new("form-data; name=\"primary_file\"; filename=\"document.pdf\""),
      } of String => JSON::Any),
    } of String => JSON::Any

    # Mock form data with file
    data = {
      "title"        => JSON::Any.new("Important Document"),
      "description"  => JSON::Any.new("This is a very important document"),
      "category"     => JSON::Any.new("document"),
      "primary_file" => JSON::Any.new(file_data),
      "tags"         => JSON::Any.new([
        JSON::Any.new("important"),
        JSON::Any.new("business"),
      ] of JSON::Any),
      "is_public"       => JSON::Any.new(false),
      "allow_downloads" => JSON::Any.new(true),
    } of String => JSON::Any

    schema = DocumentUploadSchema.new(data)
    result = schema.validate

    if result.success?
      puts "✅ Document upload validation successful!"
      puts "Title: #{schema.title}"
      puts "Category: #{schema.category}"
      if file = schema.primary_file
        puts "File: #{file["filename"]} (#{file["size"]} bytes, #{file["content_type"]})"
      end
      puts "Tags: #{schema.tags.try(&.join(", "))}"
      puts "Public: #{schema.is_public}"
    else
      puts "❌ Document upload validation failed:"
      result.errors.each do |error|
        puts "  - #{error.field}: #{error.message}"
      end
    end
  end

  def self.demonstrate_validation_errors
    puts "\n=== Validation Error Handling Example ==="

    # Submit invalid data to see error handling
    invalid_data = "first_name=J&email=invalid-email&age=12&password=123" # Too short name, invalid email, too young, weak password

    request = HTTP::Request.new("POST", "/register")
    request.headers["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = IO::Memory.new(invalid_data)

    data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
    schema = UserRegistrationSchema.new(data)
    result = schema.validate

    puts "❌ Validation errors as expected:"
    result.errors.each do |error|
      puts "  - #{error.field}: #{error.message} (#{error.code})"
      if details = error.details
        puts "    Details: #{details}"
      end
    end
  end

  def self.demonstrate_array_parsing
    puts "\n=== Array and Repeated Field Parsing ==="

    # Test different array notations
    test_cases = [
      {
        name: "Simple array notation",
        data: "tags[]=ruby&tags[]=crystal&tags[]=programming",
      },
      {
        name: "Indexed array notation",
        data: "skills[0]=Crystal&skills[1]=JavaScript&skills[2]=Docker",
      },
      {
        name: "Mixed array notation",
        data: "tags[]=web&skills[0]=Frontend&skills[1]=Backend&tags[]=development",
      },
      {
        name: "Sparse array notation",
        data: "items[0]=first&items[2]=third&items[5]=sixth",
      },
    ]

    test_cases.each do |test_case|
      puts "\n--- #{test_case[:name]} ---"
      request = HTTP::Request.new("POST", "/test")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(test_case[:data])

      parsed = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      puts "Input: #{test_case[:data]}"
      puts "Parsed: #{parsed.to_pretty_json}"
    end
  end

  # Run all demonstrations
  def self.run
    puts "🚀 Amber Schema Form Data Parser Examples"
    puts "=" * 50

    demonstrate_basic_form
    demonstrate_nested_form
    demonstrate_file_validation
    demonstrate_validation_errors
    demonstrate_array_parsing

    puts "\n✨ All examples completed!"
  end
end

# Run examples if this file is executed directly
if PROGRAM_NAME.includes?("form_data_example")
  FormDataExample.run
end
