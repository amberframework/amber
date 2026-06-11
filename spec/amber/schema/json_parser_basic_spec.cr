require "../../spec_helper"

class SimpleSchema < Amber::Schema::Definition
  field :name, String, required: true
  field :age, Int32
  field :active, Bool
end

describe "JSON Parser Basic Integration" do
  it "parses JSON and validates with schema" do
    json = <<-JSON
    {
      "name": "John Doe",
      "age": 25,
      "active": true
    }
    JSON

    # Parse JSON
    data = Amber::Schema::Parser::JSONParser.parse_string(json)
    data.should be_a(Hash(String, JSON::Any))
    data["name"].as_s.should eq("John Doe")
    data["age"].as_i.should eq(25)
    data["active"].as_bool.should be_true

    # Create schema and validate
    schema = SimpleSchema.new(data)
    result = schema.validate

    # Debug output
    unless result.success?
      puts "\nValidation errors:"
      result.errors.each do |error|
        puts "  Field: #{error.field}, Message: #{error.message}, Code: #{error.code}"
      end
    end

    result.success?.should be_true

    # Access fields
    schema.name.should eq("John Doe")
    schema.age.should eq(25)
    schema.active.should be_true
  end

  it "handles missing required fields" do
    json = <<-JSON
    {
      "age": 25
    }
    JSON

    data = Amber::Schema::Parser::JSONParser.parse_string(json)
    schema = SimpleSchema.new(data)
    result = schema.validate

    result.failure?.should be_true
    result.errors.size.should eq(1)
    result.errors.first.field.should eq("name")
    result.errors.first.code.should eq("required_field_missing")
  end
end
