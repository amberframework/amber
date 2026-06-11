# Example usage of the JSON Parser in Amber Schema

require "../../../amber"

module JsonParserExample
  # Example 1: Basic JSON parsing
  def self.basic_parsing
    json_string = <<-JSON
    {
      "name": "John Doe",
      "age": 30,
      "email": "john@example.com",
      "active": true
    }
    JSON

    result = Amber::Schema::Parser::JSONParser.parse_string(json_string)

    puts "Parsed data:"
    puts "Name: #{result["name"].as_s}"
    puts "Age: #{result["age"].as_i}"
    puts "Email: #{result["email"].as_s}"
    puts "Active: #{result["active"].as_bool}"
  end

  # Example 2: Nested JSON with arrays
  def self.nested_json
    json_string = <<-JSON
    {
      "user": {
        "id": 123,
        "profile": {
          "firstName": "Jane",
          "lastName": "Smith",
          "addresses": [
            {
              "type": "home",
              "street": "123 Main St",
              "city": "NYC",
              "zip": "10001"
            },
            {
              "type": "work",
              "street": "456 Business Ave",
              "city": "NYC",
              "zip": "10002"
            }
          ]
        }
      },
      "tags": ["developer", "crystal", "amber"]
    }
    JSON

    result = Amber::Schema::Parser::JSONParser.parse_string(json_string)

    user = result["user"].as_h
    profile = user["profile"].as_h
    addresses = profile["addresses"].as_a

    puts "User ID: #{user["id"].as_i}"
    puts "Name: #{profile["firstName"].as_s} #{profile["lastName"].as_s}"
    puts "Addresses:"
    addresses.each do |addr|
      address = addr.as_h
      puts "  #{address["type"].as_s}: #{address["street"].as_s}, #{address["city"].as_s}"
    end
  end

  # Example 3: Form data parsing
  def self.form_data_parsing
    # Simulating form data from HTTP params
    params = HTTP::Params.parse("user[name]=Alice&user[email]=alice@example.com&user[age]=25&tags[]=ruby&tags[]=crystal")

    result = Amber::Schema::Parser::JSONParser.parse_params(params)

    user = result["user"].as_h
    puts "Form data parsed:"
    puts "User name: #{user["name"].as_s}"
    puts "User email: #{user["email"].as_s}"
    puts "User age: #{user["age"].as_i}"
    puts "Tags: #{result["tags"].as_a.map(&.as_s).join(", ")}"
  end

  # Example 4: Schema with field aliasing
  def self.field_aliasing_example
    # Field aliasing example would require schema to be defined outside
    # For now, just demonstrate the parsing
    json_string = <<-JSON
    {
      "username": "bob123",
      "email": "bob@example.com",
      "active": false,
      "extra_field": "ignored"
    }
    JSON

    data = Amber::Schema::Parser::JSONParser.parse_string(json_string)

    puts "Parsed fields:"
    puts "username: #{data["username"].as_s}"
    puts "email: #{data["email"].as_s}"
    puts "active: #{data["active"].as_bool}"
  end

  # Example 5: Error handling
  def self.error_handling
    invalid_json = "{invalid json"

    begin
      Amber::Schema::Parser::JSONParser.parse_string(invalid_json)
    rescue ex : Amber::Schema::SchemaDefinitionError
      puts "Caught parsing error: #{ex.message}"
    end

    # Empty body handling
    empty_result = Amber::Schema::Parser::JSONParser.parse_string("")
    puts "Empty body returns: #{empty_result.inspect}"
  end

  # Example 6: Using ParserRegistry with HTTP requests
  def self.parser_registry_example
    # Simulate an HTTP request with JSON content
    request = HTTP::Request.new("POST", "/api/users")
    request.headers["Content-Type"] = "application/json"
    request.body = IO::Memory.new(<<-JSON
    {
      "name": "Charlie",
      "age": 28,
      "preferences": {
        "theme": "dark",
        "notifications": true
      }
    }
    JSON
    )

    # Use ParserRegistry to automatically select the right parser
    result = Amber::Schema::Parser::ParserRegistry.parse_request(request)

    puts "Parsed via registry:"
    puts "Name: #{result["name"].as_s}"
    puts "Theme: #{result["preferences"].as_h["theme"].as_s}"
  end

  # Example 7: Complex form data with nested arrays
  def self.complex_form_data
    # Simulating complex nested form data
    params = HTTP::Params.parse([
      "order[id]=123",
      "order[customer][name]=Eve",
      "order[customer][email]=eve@example.com",
      "order[items][0][product]=Widget",
      "order[items][0][quantity]=2",
      "order[items][1][product]=Gadget",
      "order[items][1][quantity]=1",
      "order[notes]=Rush delivery",
    ].join("&"))

    result = Amber::Schema::Parser::JSONParser.parse_params(params)

    order = result["order"].as_h
    customer = order["customer"].as_h
    items = order["items"].as_a

    puts "Order ID: #{order["id"].as_i}"
    puts "Customer: #{customer["name"].as_s} (#{customer["email"].as_s})"
    puts "Items:"
    items.each_with_index do |item, i|
      item_data = item.as_h
      puts "  #{i + 1}. #{item_data["product"].as_s} x#{item_data["quantity"].as_i}"
    end
    puts "Notes: #{order["notes"].as_s}"
  end

  # Run all examples
  def self.run_all
    puts "=== Basic JSON Parsing ==="
    basic_parsing
    puts "\n=== Nested JSON ==="
    nested_json
    puts "\n=== Form Data Parsing ==="
    form_data_parsing
    puts "\n=== Field Aliasing ==="
    field_aliasing_example
    puts "\n=== Error Handling ==="
    error_handling
    puts "\n=== Parser Registry ==="
    parser_registry_example
    puts "\n=== Complex Form Data ==="
    complex_form_data
  end
end

# Run examples if this file is executed directly
if PROGRAM_NAME == __FILE__
  JsonParserExample.run_all
end
