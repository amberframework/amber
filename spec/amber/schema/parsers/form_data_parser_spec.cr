require "../../../spec_helper"

describe Amber::Schema::Parser::QueryParser do
  describe "enhanced form parsing" do
    it "handles application/x-www-form-urlencoded content via ParserRegistry" do
      body = "name=John&age=30&tags[]=ruby&tags[]=crystal&user[profile][city]=NYC"
      request = HTTP::Request.new("POST", "/test")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(body)

      result = Amber::Schema::Parser::ParserRegistry.parse_request(request)

      result["name"].as_s.should eq "John"
      result["age"].as_i64.should eq 30
      result["tags"].as_a.size.should eq 2
      result["tags"].as_a[0].as_s.should eq "ruby"
      result["tags"].as_a[1].as_s.should eq "crystal"
      result["user"].as_h["profile"].as_h["city"].as_s.should eq "NYC"
    end

    it "handles empty form data" do
      request = HTTP::Request.new("POST", "/test")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new("")

      result = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      result.should be_empty
    end

    it "handles missing content type" do
      request = HTTP::Request.new("POST", "/test")
      request.body = IO::Memory.new("name=test")

      # This should fall back to query parameters (empty in this case)
      result = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      result.should be_empty
    end

    it "handles unknown content type" do
      request = HTTP::Request.new("POST", "/test")
      request.headers["Content-Type"] = "text/plain"
      request.body = IO::Memory.new("some text")

      result = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      result.should be_empty
    end
  end

  describe ".parse_params_to_nested" do
    it "parses simple key-value pairs" do
      params = HTTP::Params.parse("name=John&age=30&active=true")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["name"].as_s.should eq "John"
      result["age"].as_i64.should eq 30
      result["active"].as_bool.should eq true
    end

    it "parses array notation with indices" do
      params = HTTP::Params.parse("items[0]=first&items[1]=second&items[2]=third")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["items"].as_a.size.should eq 3
      result["items"].as_a[0].as_s.should eq "first"
      result["items"].as_a[1].as_s.should eq "second"
      result["items"].as_a[2].as_s.should eq "third"
    end

    it "parses simple array notation" do
      params = HTTP::Params.parse("tags[]=ruby&tags[]=crystal&tags[]=amber")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["tags"].as_a.size.should eq 3
      result["tags"].as_a[0].as_s.should eq "ruby"
      result["tags"].as_a[1].as_s.should eq "crystal"
      result["tags"].as_a[2].as_s.should eq "amber"
    end

    it "parses nested object notation" do
      params = HTTP::Params.parse("user[name]=John&user[profile][age]=30&user[profile][city]=NYC")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["user"].as_h["name"].as_s.should eq "John"
      result["user"].as_h["profile"].as_h["age"].as_i64.should eq 30
      result["user"].as_h["profile"].as_h["city"].as_s.should eq "NYC"
    end

    it "parses dot notation" do
      params = HTTP::Params.parse("user.name=John&user.profile.age=30")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["user"].as_h["name"].as_s.should eq "John"
      result["user"].as_h["profile"].as_h["age"].as_i64.should eq 30
    end

    it "handles mixed notation" do
      params = HTTP::Params.parse("user[name]=John&tags[]=ruby&settings.theme=dark&count=5")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["user"].as_h["name"].as_s.should eq "John"
      result["tags"].as_a[0].as_s.should eq "ruby"
      result["settings"].as_h["theme"].as_s.should eq "dark"
      result["count"].as_i64.should eq 5
    end

    it "handles URL encoding" do
      params = HTTP::Params.parse("message=Hello%20World&email=test%40example.com")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["message"].as_s.should eq "Hello World"
      result["email"].as_s.should eq "test@example.com"
    end

    it "parses boolean values" do
      params = HTTP::Params.parse("active=true&disabled=false&enabled=1&hidden=0")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["active"].as_bool.should eq true
      result["disabled"].as_bool.should eq false
      result["enabled"].as_i64.should eq 1
      result["hidden"].as_i64.should eq 0
    end

    it "parses numeric values" do
      params = HTTP::Params.parse("int_val=42&float_val=3.14&negative=-5")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["int_val"].as_i64.should eq 42
      result["float_val"].as_f.should eq 3.14
      result["negative"].as_i64.should eq -5
    end

    it "handles empty values" do
      params = HTTP::Params.parse("empty=&blank=&name=John")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["empty"].as_s.should eq ""
      result["blank"].as_s.should eq ""
      result["name"].as_s.should eq "John"
    end

    it "handles sparse arrays" do
      params = HTTP::Params.parse("items[0]=first&items[2]=third&items[5]=sixth")
      result = Amber::Schema::Parser::QueryParser.parse_params_to_nested(params)

      result["items"].as_a.size.should eq 6
      result["items"].as_a[0].as_s.should eq "first"
      result["items"].as_a[1].raw.should be_nil
      result["items"].as_a[2].as_s.should eq "third"
      result["items"].as_a[3].raw.should be_nil
      result["items"].as_a[4].raw.should be_nil
      result["items"].as_a[5].as_s.should eq "sixth"
    end
  end
end

describe Amber::Schema::Parser::FileUploadValidator do
  describe ".validate_file" do
    it "validates file size constraints" do
      file_data = JSON::Any.new({
        "filename"     => JSON::Any.new("test.jpg"),
        "content_type" => JSON::Any.new("image/jpeg"),
        "size"         => JSON::Any.new(1000_i64),
        "content"      => JSON::Any.new("fake content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any)

      options = {
        "max_size" => JSON::Any.new(500_i64),
      } of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("avatar", file_data, options)
      errors.size.should eq 1
      errors[0].field.should eq "avatar"
      errors[0].code.should eq "file_too_large"
    end

    it "validates content type restrictions" do
      file_data = JSON::Any.new({
        "filename"     => JSON::Any.new("test.txt"),
        "content_type" => JSON::Any.new("text/plain"),
        "size"         => JSON::Any.new(100_i64),
        "content"      => JSON::Any.new("fake content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any)

      options = {
        "allowed_types" => JSON::Any.new([
          JSON::Any.new("image/jpeg"),
          JSON::Any.new("image/png"),
        ] of JSON::Any),
      } of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("avatar", file_data, options)
      errors.size.should eq 1
      errors[0].field.should eq "avatar"
      errors[0].code.should eq "invalid_content_type"
    end

    it "validates file extensions" do
      file_data = JSON::Any.new({
        "filename"     => JSON::Any.new("test.exe"),
        "content_type" => JSON::Any.new("application/octet-stream"),
        "size"         => JSON::Any.new(100_i64),
        "content"      => JSON::Any.new("fake content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any)

      options = {
        "allowed_extensions" => JSON::Any.new([
          JSON::Any.new(".jpg"),
          JSON::Any.new(".png"),
          JSON::Any.new(".gif"),
        ] of JSON::Any),
      } of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("document", file_data, options)
      errors.size.should eq 1
      errors[0].field.should eq "document"
      errors[0].code.should eq "invalid_file_extension"
    end

    it "validates filename patterns" do
      file_data = JSON::Any.new({
        "filename"     => JSON::Any.new("invalid@file&name.jpg"),
        "content_type" => JSON::Any.new("image/jpeg"),
        "size"         => JSON::Any.new(100_i64),
        "content"      => JSON::Any.new("fake content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any)

      options = {
        "filename_pattern" => JSON::Any.new("^[a-zA-Z0-9._-]+$"),
      } of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("avatar", file_data, options)
      errors.size.should eq 1
      errors[0].field.should eq "avatar"
      errors[0].code.should eq "invalid_filename_pattern"
    end

    it "accepts valid files" do
      file_data = JSON::Any.new({
        "filename"     => JSON::Any.new("profile.jpg"),
        "content_type" => JSON::Any.new("image/jpeg"),
        "size"         => JSON::Any.new(500_i64),
        "content"      => JSON::Any.new("fake content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any)

      options = {
        "max_size"           => JSON::Any.new(1000_i64),
        "allowed_types"      => JSON::Any.new([JSON::Any.new("image/jpeg")] of JSON::Any),
        "allowed_extensions" => JSON::Any.new([JSON::Any.new(".jpg")] of JSON::Any),
        "filename_pattern"   => JSON::Any.new("^[a-zA-Z0-9._-]+$"),
      } of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("avatar", file_data, options)
      errors.size.should eq 0
    end

    it "rejects non-file data" do
      file_data = JSON::Any.new({
        "not_a_file" => JSON::Any.new("value"),
      } of String => JSON::Any)

      options = {} of String => JSON::Any

      errors = Amber::Schema::Parser::FileUploadValidator.validate_file("avatar", file_data, options)
      errors.size.should eq 1
      errors[0].field.should eq "avatar"
      errors[0].code.should eq "not_a_file"
    end
  end
end
