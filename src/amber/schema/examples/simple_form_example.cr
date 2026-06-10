require "http"

# Simple demonstration of the enhanced form parsing capabilities
module SimpleFormExample
  # Mock request helper
  def self.create_form_request(content_type : String, body : String)
    request = HTTP::Request.new("POST", "/test")
    request.headers["Content-Type"] = content_type
    request.body = IO::Memory.new(body)
    request
  end

  def self.demonstrate_url_encoded_parsing
    puts "=== URL-encoded Form Parsing Example ==="

    # Test complex nested form data
    form_data = [
      "user[name]=Jane Smith",
      "user[email]=jane@example.com",
      "user[profile][age]=30",
      "user[profile][city]=New York",
      "tags[]=ruby",
      "tags[]=crystal",
      "tags[]=programming",
      "skills[0]=Backend",
      "skills[1]=Frontend",
      "skills[3]=DevOps", # Sparse array
      "active=true",
      "score=95.5",
    ].join("&")

    puts "Input form data:"
    puts form_data
    puts "\nParsed structure:"

    # Parse using HTTP::Params directly to show the enhanced parsing
    params = HTTP::Params.parse(form_data)
    puts "Raw params: #{params.to_h}"

    puts "\nThis would be further processed by the enhanced QueryParser"
    puts "to create proper nested JSON structures for the Schema API."
  end

  def self.demonstrate_file_upload_structure
    puts "\n=== File Upload Data Structure Example ==="

    puts "When processing multipart/form-data with files, the parser creates:"
    puts "structures like this for file fields:"

    file_structure = {
      "filename"     => "document.pdf",
      "content_type" => "application/pdf",
      "size"         => 1024000,
      "content"      => "[file content bytes]",
      "headers"      => {
        "Content-Type"        => "application/pdf",
        "Content-Disposition" => "form-data; name=\"document\"; filename=\"document.pdf\"",
      },
    }

    puts file_structure

    puts "\nThis allows the Schema API to:"
    puts "- Validate file size (max_size option)"
    puts "- Check content types (allowed_types option)"
    puts "- Validate file extensions (allowed_extensions option)"
    puts "- Check filename patterns (filename_pattern option)"
  end

  def self.demonstrate_array_parsing
    puts "\n=== Array Parsing Examples ==="

    test_cases = [
      {
        name: "Simple array notation",
        data: "tags[]=ruby&tags[]=crystal&tags[]=programming",
      },
      {
        name: "Indexed arrays",
        data: "items[0]=first&items[1]=second&items[2]=third",
      },
      {
        name: "Sparse arrays",
        data: "values[0]=a&values[2]=c&values[5]=f",
      },
      {
        name: "Mixed nested data",
        data: "user[tags][]=admin&user[tags][]=developer&user[profile][name]=John",
      },
    ]

    test_cases.each do |test_case|
      puts "\n--- #{test_case[:name]} ---"
      puts "Input: #{test_case[:data]}"

      params = HTTP::Params.parse(test_case[:data])
      puts "Parsed params: #{params.to_h}"
      puts "(Enhanced parser would create proper nested JSON structure)"
    end
  end

  def self.run
    puts "🚀 Enhanced Form Data Parser Examples for Amber Schema API"
    puts "=" * 60

    demonstrate_url_encoded_parsing
    demonstrate_file_upload_structure
    demonstrate_array_parsing

    puts "\n✨ Examples completed!"
    puts "\nKey Features Implemented:"
    puts "• Enhanced URL-encoded form parsing with bracket notation"
    puts "• Nested object support: user[profile][name]"
    puts "• Array support: tags[]=item or items[0]=value"
    puts "• Sparse array handling"
    puts "• File upload data structures for multipart forms"
    puts "• Integration with Schema API validation system"
    puts "• Type coercion for form values (strings, numbers, booleans)"
  end
end

# Run the examples
SimpleFormExample.run
