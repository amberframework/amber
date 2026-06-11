# Example demonstrating XML parser usage with Amber Schema
require "../../schema"

# Define a schema for parsing XML book data
class BookXMLSchema < Amber::Schema::Definition
  # Basic field extraction (using default parsing)
  field :isbn, String, required: true
  field :title, String, required: true
  field :author, String, required: true
  field :price, Float32
  field :year, Int32

  # XPath-based extraction (advanced usage)
  field :book_id, String, xpath: "//book/@id"
  field :genre, String, xpath: "//book/metadata/genre"
  field :publisher, String, xpath: "//book/metadata/publisher"

  # Array extraction (note: XPath arrays need additional work, use basic parsing for now)
  # field :tags, Array(String), xpath: "//book/tags/tag"

  # Namespace-aware extraction
  field :isbn13, String, xpath: "//isbn:code", namespaces: {"isbn" => "http://isbn.org/"}

  validates_to BookResponse, BookError
  content_type "application/xml", "text/xml"
end

# Response types
class BookResponse
  def initialize(@isbn : String, @title : String, @author : String,
                 @price : Float32? = nil, @year : Int32? = nil, @book_id : String? = nil,
                 @genre : String? = nil, @publisher : String? = nil, @isbn13 : String? = nil)
  end

  property isbn : String
  property title : String
  property author : String
  property price : Float32?
  property year : Int32?
  property book_id : String?
  property genre : String?
  property publisher : String?
  property isbn13 : String?

  def to_json(json : JSON::Builder)
    json.object do
      json.field "isbn", isbn
      json.field "title", title
      json.field "author", author
      json.field "price", price if price
      json.field "year", year if year
      json.field "book_id", book_id if book_id
      json.field "genre", genre if genre
      json.field "publisher", publisher if publisher
      json.field "isbn13", isbn13 if isbn13
    end
  end
end

class BookError
  def initialize(@errors : Array(String))
  end

  property errors : Array(String)

  def to_json(json : JSON::Builder)
    json.object do
      json.field "errors", errors
    end
  end
end

# Example usage
module XMLParserExample
  def self.run
    puts "=== Amber Schema XML Parser Example ==="

    # Example XML data
    xml_data = %(
      <book id="bk001" xmlns:isbn="http://isbn.org/">
        <title>Crystal Programming Guide</title>
        <author>John Smith</author>
        <isbn>978-0123456789</isbn>
        <isbn:code>978-0123456789012</isbn:code>
        <price>39.99</price>
        <year>2024</year>
        <metadata>
          <genre>Programming</genre>
          <publisher>Tech Books Publishing</publisher>
        </metadata>
        <tags>
          <tag>crystal</tag>
          <tag>programming</tag>
          <tag>language</tag>
        </tags>
      </book>
    )

    puts "\n--- Basic XML Parsing ---"

    # Basic parsing (without schema)
    basic_result = Amber::Schema::Parser::XMLParser.parse_string(xml_data)
    puts "Basic parsing result:"
    basic_result.each do |key, value|
      puts "  #{key}: #{value}"
    end

    puts "\n--- Schema-based XML Parsing ---"

    # Schema-based parsing
    schema = BookXMLSchema.new(basic_result)
    validation_result = schema.validate

    if validation_result.success?
      puts "✓ XML validation successful!"
      puts "Title: #{schema.title}"
      puts "Author: #{schema.author}"
      puts "ISBN: #{schema.isbn}"
      puts "Price: #{schema.price}"
      puts "Year: #{schema.year}"
      puts "Book ID: #{schema.book_id}" if schema.book_id
      puts "Genre: #{schema.genre}" if schema.genre
      puts "Publisher: #{schema.publisher}" if schema.publisher

      # Convert to response object
      response = BookResponse.new(
        isbn: schema.isbn.not_nil!,
        title: schema.title.not_nil!,
        author: schema.author.not_nil!,
        price: schema.price,
        year: schema.year,
        book_id: schema.book_id,
        genre: schema.genre,
        publisher: schema.publisher,
        isbn13: schema.isbn13
      )

      puts "\nJSON Response:"
      puts response.to_json
    else
      puts "✗ XML validation failed:"
      validation_result.errors.each do |error|
        puts "  - #{error.field}: #{error.message}"
      end
    end

    puts "\n--- ParserRegistry Integration ---"

    # Simulate HTTP request with XML body
    io = IO::Memory.new(xml_data)
    request = HTTP::Request.new("POST", "/books", body: io)
    request.headers["Content-Type"] = "application/xml"

    # Parse through registry
    registry_result = Amber::Schema::Parser::ParserRegistry.parse_request(request)
    puts "Registry parsing result keys: #{registry_result.keys}"

    puts "\n--- Content-Type Auto-Detection ---"

    # Test auto-detection
    io2 = IO::Memory.new(xml_data)
    request2 = HTTP::Request.new("POST", "/books", body: io2)
    # No Content-Type header - should auto-detect XML

    auto_result = Amber::Schema::Parser::ParserRegistry.parse_request(request2)
    puts "Auto-detected parsing result keys: #{auto_result.keys}"

    puts "\n--- Error Handling ---"

    # Test with malformed XML
    malformed_xml = %(<book><title>Unclosed tag<author>Test</book>)

    begin
      malformed_result = Amber::Schema::Parser::XMLParser.parse_string(malformed_xml)
      puts "✓ Malformed XML handled gracefully"
      puts "Result keys: #{malformed_result.keys}"
    rescue ex : Amber::Schema::SchemaDefinitionError
      puts "✗ XML parsing error: #{ex.message}"
    end

    puts "\n=== Example Complete ==="
  end
end

# Run the example if this file is executed directly
if PROGRAM_NAME.includes?("xml_parser_example")
  XMLParserExample.run
end
