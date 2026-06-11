require "../../spec_helper"

# Test schemas for integration tests
class CreateUserSchema < Amber::Schema::Definition
  field :name, String, required: true, min_length: 2, max_length: 50
  field :email, String, required: true, format: "email"
  field :age, Int32, min: 18, max: 120
  # field :tags, Array(String)  # TODO: Fix generic array types
  field :active, Bool, default: true
  # field :metadata, Hash(String, JSON::Any)  # TODO: Fix generic hash types
end

class UpdateUserSchema < Amber::Schema::Definition
  field :name, String, min_length: 2, max_length: 50
  field :email, String, format: "email"
  field :age, Int32, min: 18, max: 120
  # field :tags, Array(String)  # TODO: Fix generic array types
  field :active, Bool
end

class NestedAddressSchema < Amber::Schema::Definition
  field :street, String, required: true
  field :city, String, required: true
  field :zip, String, pattern: "^\\d{5}$"
  field :country, String, default: "USA"
end

class UserWithAddressSchema < Amber::Schema::Definition
  field :name, String, required: true
  field :email, String, required: true
  nested :address, NestedAddressSchema
end

# Integration tests for JSON Parser with Schema validation
describe "JSON Parser Integration" do
  describe "with Schema Definition" do
    it "parses and validates JSON request body" do
      json = <<-JSON
      {
        "name": "John Doe",
        "email": "john@example.com",
        "age": 25,
        "tags": ["developer", "crystal"],
        "metadata": {
          "source": "api",
          "version": "1.0"
        }
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      schema = CreateUserSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.name.should eq("John Doe")
      schema.email.should eq("john@example.com")
      schema.age.should eq(25)
      # schema.tags.should eq(["developer", "crystal"])  # TODO
      schema.active.should be_true # default value
    end

    it "handles validation errors" do
      json = <<-JSON
      {
        "name": "J",
        "email": "invalid-email",
        "age": 150
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      schema = CreateUserSchema.new(data)
      result = schema.validate

      result.failure?.should be_true
      result.errors.size.should be >= 3

      errors_by_field = result.errors_by_field
      errors_by_field["name"].first.code.should eq("invalid_length")
      errors_by_field["email"].first.code.should eq("invalid_format")
      errors_by_field["age"].first.code.should eq("out_of_range")
    end

    it "parses form data with type coercion" do
      params = HTTP::Params.parse("name=Alice&email=alice@example.com&age=30&tags[]=ruby&tags[]=amber&active=false")
      data = Amber::Schema::Parser::JSONParser.parse_params(params)
      schema = CreateUserSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.name.should eq("Alice")
      schema.age.should eq(30)      # String "30" coerced to Int32
      schema.active.should be_false # String "false" coerced to Bool
      # schema.tags.should eq(["ruby", "amber"])  # TODO
    end

    it "handles nested schemas" do
      json = <<-JSON
      {
        "name": "Bob Smith",
        "email": "bob@example.com",
        "address": {
          "street": "123 Main St",
          "city": "New York",
          "zip": "10001"
        }
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      schema = UserWithAddressSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.name.should eq("Bob Smith")

      address = schema.address_schema
      address.should_not be_nil
      if addr = address
        addr.street.should eq("123 Main St")
        addr.city.should eq("New York")
        addr.zip.should eq("10001")
        addr.country.should eq("USA") # default value
      end
    end

    it "handles empty and null values" do
      json = <<-JSON
      {
        "name": "Empty Test",
        "email": "test@example.com",
        "age": null,
        "tags": [],
        "metadata": {}
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      schema = CreateUserSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.age.should be_nil
      # schema.tags.should eq([] of String)  # TODO
      # schema.metadata.should eq({} of String => JSON::Any)  # TODO
    end

    it "handles array root elements" do
      json = <<-JSON
      [
        {"id": 1, "name": "Item 1"},
        {"id": 2, "name": "Item 2"}
      ]
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      data.has_key?("data").should be_true
      data["data"].as_a.size.should eq(2)
    end

    it "parses complex nested form data" do
      params = HTTP::Params.parse([
        "user[name]=Complex User",
        "user[email]=complex@example.com",
        "user[profile][bio]=Developer",
        "user[profile][website]=https://example.com",
        "user[addresses][0][type]=home",
        "user[addresses][0][city]=NYC",
        "user[addresses][1][type]=work",
        "user[addresses][1][city]=SF",
      ].join("&"))

      data = Amber::Schema::Parser::JSONParser.parse_params(params)

      user = data["user"].as_h
      user["name"].as_s.should eq("Complex User")

      profile = user["profile"].as_h
      profile["bio"].as_s.should eq("Developer")

      # Note: Array index notation is not yet supported
      # addresses = user["addresses"].as_a
      # addresses.size.should eq(2)
    end
  end

  describe "edge cases" do
    it "handles malformed JSON gracefully" do
      malformed = "{\"name\": \"test\", invalid}"

      expect_raises(Amber::Schema::SchemaDefinitionError, /Invalid JSON/) do
        Amber::Schema::Parser::JSONParser.parse_string(malformed)
      end
    end

    it "handles deeply nested structures" do
      json = <<-JSON
      {
        "level1": {
          "level2": {
            "level3": {
              "level4": {
                "value": "deep"
              }
            }
          }
        }
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      value = data["level1"].as_h["level2"].as_h["level3"].as_h["level4"].as_h["value"].as_s
      value.should eq("deep")
    end

    it "handles unicode and special characters" do
      json = <<-JSON
      {
        "name": "José García",
        "emoji": "🚀",
        "special": "Line1\\nLine2\\tTabbed",
        "japanese": "こんにちは"
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      data["name"].as_s.should eq("José García")
      data["emoji"].as_s.should eq("🚀")
      data["japanese"].as_s.should eq("こんにちは")
    end

    it "handles scientific notation numbers" do
      json = <<-JSON
      {
        "small": 1.23e-10,
        "large": 9.87e20,
        "negative": -4.56e-5
      }
      JSON

      data = Amber::Schema::Parser::JSONParser.parse_string(json)
      data["small"].as_f.should be_close(1.23e-10, 1e-15)
      data["large"].as_f.should be_close(9.87e20, 1e15)
      data["negative"].as_f.should be_close(-4.56e-5, 1e-10)
    end
  end
end
