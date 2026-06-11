# Amber Schema XML Parser

## Overview

The XML parser provides comprehensive XML parsing capabilities for the Amber Schema system, supporting both basic XML-to-hash conversion and advanced XPath-based field extraction.

## Features

### 1. Basic XML Parsing
- Parses XML documents into `Hash(String, JSON::Any)` format
- Handles nested elements with dot notation (`parent.child`)
- Extracts attributes with `@` notation (`element@attribute`)
- Supports mixed content with `#text` notation
- Handles empty elements and self-closing tags
- Manages CDATA sections (content extraction)

### 2. XPath-based Field Extraction
- Schema-driven extraction using XPath expressions
- Support for simple XPath queries like `//element/child`
- Attribute extraction with `//element/@attribute`
- Array extraction for multiple matching elements
- Basic namespace support

### 3. Content-Type Integration
- Automatic parser selection via `ParserRegistry`
- Supports standard XML content types:
  - `application/xml`
  - `text/xml`
  - `application/xhtml+xml`
- Auto-detection from content when no Content-Type header is present

### 4. Error Handling
- Graceful handling of malformed XML
- Clear error messages for schema validation failures
- Robust fallback mechanisms

## Usage

### Basic XML Parsing

```crystal
xml_string = %(
  <book id="123">
    <title>Crystal Programming</title>
    <author>John Doe</author>
    <metadata>
      <pages>350</pages>
      <genre>Programming</genre>
    </metadata>
  </book>
)

data = Amber::Schema::Parser::XMLParser.parse_string(xml_string)
# Result:
# {
#   "book@id" => "123",
#   "book#text" => "Crystal Programming John Doe 350 Programming",
#   "book.title" => "Crystal Programming",
#   "book.author" => "John Doe", 
#   "book.metadata.pages" => "350",
#   "book.metadata.genre" => "Programming"
# }
```

### Schema-based XML Parsing

```crystal
class BookSchema < Amber::Schema::Definition
  # Basic fields (extracted from flattened structure)
  field :title, String, required: true
  field :author, String, required: true
  
  # XPath-based extraction
  field :book_id, String, xpath: "//book/@id"
  field :pages, Int32, xpath: "//book/metadata/pages"
  field :tags, Array(String), xpath: "//book/tags/tag"
  
  # Namespace-aware extraction
  field :isbn, String, xpath: "//isbn:code", namespaces: {"isbn" => "http://isbn.org/"}
  
  validates_to BookResponse, BookError
  content_type "application/xml"
end

# Parse with schema
data = Amber::Schema::Parser::XMLParser.parse_string(xml_string)
schema = BookSchema.new(data)
result = schema.validate

if result.success?
  puts schema.title    # "Crystal Programming"
  puts schema.book_id  # "123"
  puts schema.pages    # 350
end
```

### HTTP Request Parsing

```crystal
# Through registry (automatic content-type detection)
request = HTTP::Request.new("POST", "/books", body: xml_body)
request.headers["Content-Type"] = "application/xml"

data = Amber::Schema::Parser::ParserRegistry.parse_request(request)

# Direct XML parsing
data = Amber::Schema::Parser::XMLParser.parse_request(request)
```

### Controller Integration

```crystal
class BooksController < ApplicationController
  include Amber::Schema::ControllerIntegration

  def create
    # Automatically parses XML based on Content-Type
    data = parse_request_data
    schema = BookSchema.new(data)
    
    if result = schema.validate_typed
      case result
      when Success
        # Process valid data
        book = create_book(result.value)
        render json: book
      when Failure
        # Handle validation errors
        render json: {errors: result.error.errors}, status: 422
      end
    end
  end
end
```

## XML Structure Handling

### Element Naming Convention
- **Simple elements**: `elementName`
- **Nested elements**: `parent.child.grandchild`
- **Attributes**: `element@attributeName`
- **Mixed content**: `element#text` for text content when element has children

### Special Cases
- **Empty elements**: `<empty></empty>` → `{"empty" => ""}`
- **Self-closing tags**: `<tag/>` → `{"tag" => ""}`
- **Whitespace-only content**: Trimmed to empty string
- **Duplicate elements**: Last element wins (limitation of current implementation)

### Namespace Handling
```crystal
# XML with namespaces
xml = %(
  <catalog xmlns:book="http://example.com/books">
    <book:item isbn="123">
      <book:title>Example</book:title>
    </book:item>
  </catalog>
)

# Schema with namespace definitions
class NamespacedSchema < Amber::Schema::Definition
  field :title, String, 
        xpath: "//book:title", 
        namespaces: {"book" => "http://example.com/books"}
  field :isbn, String, 
        xpath: "//book:item/@isbn", 
        namespaces: {"book" => "http://example.com/books"}
end
```

## XPath Support

The XML parser includes a simplified XPath implementation supporting:

### Supported XPath Expressions
- `//elementName` - Find all elements with given name
- `//parent/child` - Find child elements of parent
- `//element/@attribute` - Extract attribute values
- `//namespace:element` - Namespace-aware element selection

### XPath Limitations
- No complex predicates (`[condition]`)
- No advanced axes (`preceding::`, `following::`, etc.)
- Limited function support
- Simple namespace prefix matching only

### Examples
```crystal
# Find all book titles
field :titles, Array(String), xpath: "//book/title"

# Extract book IDs from attributes  
field :book_ids, Array(String), xpath: "//book/@id"

# Namespace-aware extraction
field :isbn, String, xpath: "//isbn:code", namespaces: {"isbn" => "http://isbn.org/"}
```

## Error Handling

### XML Parsing Errors
```crystal
begin
  result = XMLParser.parse_string(malformed_xml)
rescue Amber::Schema::SchemaDefinitionError => ex
  puts "XML parsing failed: #{ex.message}"
end
```

### Schema Validation Errors
```crystal
schema = BookSchema.new(data)
result = schema.validate

unless result.success?
  result.errors.each do |error|
    puts "#{error.field}: #{error.message} (#{error.code})"
  end
end
```

## Registry Configuration

The XML parser automatically registers with the ParserRegistry for these content types:

```crystal
# Default registrations (automatically configured)
ParserRegistry.register("application/xml", "xml")
ParserRegistry.register("text/xml", "xml") 
ParserRegistry.register("application/xhtml+xml", "xml")

# Custom registration example
ParserRegistry.register("application/soap+xml", "xml")
```

## Performance Considerations

### Parsing Performance
- Basic parsing is optimized for speed
- XPath queries add overhead
- Large XML documents may require streaming (not yet implemented)

### Memory Usage
- Full document is loaded into memory
- Parsed structure uses JSON::Any for type flexibility
- Consider document size for high-volume applications

## Future Enhancements

### Planned Features
1. **Enhanced XPath Support**
   - Predicates and filters
   - More XPath functions
   - Better namespace handling

2. **Streaming Parser**
   - SAX-style parsing for large documents
   - Memory-efficient processing

3. **Advanced Validation**
   - XML Schema (XSD) validation
   - Custom validation rules

4. **Performance Optimizations**
   - Selective parsing based on schema
   - Caching mechanisms

## Examples

See `src/amber/schema/examples/xml_parser_example.cr` for a comprehensive example demonstrating all features.

## Limitations

### Current Limitations
1. **XPath Implementation**: Basic support only, full XPath not implemented
2. **Duplicate Elements**: Only last element preserved in basic parsing
3. **Large Documents**: No streaming support, entire document loaded to memory
4. **Namespace Support**: Limited to prefix matching
5. **CDATA**: Content extracted but not specially marked

### Crystal XML API Limitations
- Limited XML node introspection capabilities
- Lenient parsing (may not catch all malformed XML)
- Basic namespace support in underlying library

## Migration from JSON Parser

XML parsing follows similar patterns to JSON parsing:

```crystal
# JSON parsing
json_data = JSONParser.parse_string(json_string)

# XML parsing  
xml_data = XMLParser.parse_string(xml_string)

# Both produce Hash(String, JSON::Any) for schema validation
schema = MySchema.new(xml_data)  # Same as JSON workflow
```

The main difference is in the data structure - XML produces flattened key names with dot notation for hierarchy.