require "../src/amber/schema"

module Example
  # Example custom type - Money stored as cents
  struct Money
    getter cents : Int64

    def initialize(@cents : Int64)
    end

    def to_s(io)
      io << "$"
      io << (cents / 100)
      io << "."
      io << (cents % 100).to_s.rjust(2, '0')
    end
  end

  # Register custom coercion for Money type
  Amber::Schema::TypeCoercion.register("Example::Money") do |value|
    case raw = value.raw
    when String
      # Parse strings like "$10.50" or "10.50"
      cleaned = raw.gsub(/[$,]/, "")
      if match = cleaned.match(/^(\d+)\.(\d{2})$/)
        dollars = match[1].to_i64
        cents = match[2].to_i64
        total_cents = (dollars * 100) + cents
        JSON::Any.new(total_cents)
      else
        nil
      end
    when Int32, Int64
      # Treat integers as cents
      JSON::Any.new(raw.to_i64)
    when Float32, Float64
      # Convert float dollars to cents
      cents = (raw * 100).round.to_i64
      JSON::Any.new(cents)
    else
      nil
    end
  end

  # Example schema using type coercion
  class ProductSchema < Amber::Schema::Definition
    field :name, String, required: true
    field :price, Money # Will use custom coercion
    field :quantity, Int32
    field :in_stock, Bool
    field :tags, Array(String)
    field :metadata, Hash(String, String)
    field :created_at, Time
    field :product_id, UUID
  end

  # Example usage
  def self.run_examples
    puts "=== Type Coercion Examples ==="
    puts

    # Example 1: All values as strings (common from form data)
    data1 = {
      "name"       => JSON::Any.new("Widget"),
      "price"      => JSON::Any.new("$19.99"),
      "quantity"   => JSON::Any.new("100"),
      "in_stock"   => JSON::Any.new("true"),
      "tags"       => JSON::Any.new("electronics,gadgets,new"),
      "metadata"   => JSON::Any.new(%[{"color": "blue", "size": "large"}]),
      "created_at" => JSON::Any.new("2023-12-25T10:30:00Z"),
      "product_id" => JSON::Any.new("550e8400-e29b-41d4-a716-446655440000"),
    }

    schema1 = ProductSchema.new(data1)
    result1 = schema1.validate

    puts "Example 1 - String inputs:"
    puts "  Valid: #{result1.success?}"
    puts "  Name: #{schema1.name}"
    puts "  Price: #{schema1.price}" # Would need to implement Money getter
    puts "  Quantity: #{schema1.quantity}"
    puts "  In Stock: #{schema1.in_stock}"
    puts "  Tags: #{schema1.tags}"
    puts "  Created At: #{schema1.created_at}"
    puts "  Product ID: #{schema1.product_id}"
    puts

    # Example 2: Mixed types (common from JSON)
    data2 = {
      "name"       => JSON::Any.new("Gadget"),
      "price"      => JSON::Any.new(2999), # Cents as integer
      "quantity"   => JSON::Any.new(50.0), # Float that can be exact int
      "in_stock"   => JSON::Any.new(1),    # Integer as boolean
      "tags"       => JSON::Any.new(["tech", "popular"]),
      "metadata"   => JSON::Any.new({"weight" => "500g"}),
      "created_at" => JSON::Any.new(1703502600_i64), # Unix timestamp
      "product_id" => JSON::Any.new("123e4567-e89b-12d3-a456-426614174000"),
    }

    schema2 = ProductSchema.new(data2)
    result2 = schema2.validate

    puts "Example 2 - Mixed types:"
    puts "  Valid: #{result2.success?}"
    puts "  Name: #{schema2.name}"
    puts "  Quantity: #{schema2.quantity}"
    puts "  In Stock: #{schema2.in_stock}"
    puts "  Tags: #{schema2.tags}"
    puts "  Created At: #{schema2.created_at}"
    puts

    # Example 3: Various boolean representations
    bool_examples = [
      ["yes", true],
      ["no", false],
      ["on", true],
      ["off", false],
      ["enabled", true],
      ["disabled", false],
      ["1", true],
      ["0", false],
    ]

    puts "Example 3 - Boolean variations:"
    bool_examples.each do |input, expected|
      data = {"in_stock" => JSON::Any.new(input)}
      schema = ProductSchema.new(data)
      puts "  '#{input}' -> #{schema.in_stock} (expected: #{expected})"
    end
    puts

    # Example 4: Invalid data to show error handling
    data4 = {
      "name"       => JSON::Any.new("Invalid Product"),
      "price"      => JSON::Any.new("not a price"),
      "quantity"   => JSON::Any.new("not a number"),
      "in_stock"   => JSON::Any.new("maybe"),
      "created_at" => JSON::Any.new("not a date"),
      "product_id" => JSON::Any.new("not-a-uuid"),
    }

    schema4 = ProductSchema.new(data4)
    result4 = schema4.validate

    puts "Example 4 - Invalid data:"
    puts "  Valid: #{result4.success?}"
    puts "  Errors:"
    result4.errors.each do |error|
      puts "    - #{error.field}: #{error.message}"
    end
  end
end

# Run the examples
Example.run_examples
