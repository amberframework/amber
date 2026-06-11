require "../../spec_helper"

# Integration tests for Schema API with form data parsing

# Test schemas
class UserRegistrationSchema < Amber::Schema::Definition
  field :name, String, required: true, min_length: 2
  field :email, String, required: true, format: "email"
  field :age, Int32, min: 18, max: 120
  field :terms_accepted, Bool, required: true
end

class UserProfileSchema < Amber::Schema::Definition
  # Nested user data using bracket notation
  field :user_name, String, as: "user[name]", required: true
  field :user_email, String, as: "user[email]", required: true, format: "email"
  field :address_street, String, as: "user[address][street]"
  field :address_city, String, as: "user[address][city]"
  field :tags, Array(String), repeated: true
end

class TagsSchema < Amber::Schema::Definition
  field :tags, Array(String), required: true
  field :categories, Array(String)
end

class StrictSchema < Amber::Schema::Definition
  field :name, String, required: true, min_length: 5
  field :email, String, required: true, format: "email"
  field :age, Int32, required: true, min: 21
end

class FileUploadSchema < Amber::Schema::Definition
  field :avatar, Hash(String, JSON::Any), max_size: 1048576
  field :name, String, required: true
end

class FileSizeSchema < Amber::Schema::Definition
  field :document, Hash(String, JSON::Any), max_size: 102400
end

class ImageOnlySchema < Amber::Schema::Definition
  field :image, Hash(String, JSON::Any), max_size: 1000000
end

class MultiFileSchema < Amber::Schema::Definition
  field :attachments, Array(Hash(String, JSON::Any)), required: true
end

class CompleteFormSchema < Amber::Schema::Definition
  field :title, String, required: true, min_length: 3
  field :description, String
  field :category, String
  field :featured_image, Hash(String, JSON::Any)
  field :attachments, Array(Hash(String, JSON::Any))
  field :tags, Array(String)
  field :published, Bool, default: false
end

describe "Schema Form Integration" do
  describe "URL-encoded form parsing" do
    it "validates simple form data" do
      # Simulate form submission
      body = "name=John&email=john@example.com&age=25&terms_accepted=true"
      request = HTTP::Request.new("POST", "/register")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(body)

      # Parse the request
      data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      schema = UserRegistrationSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.name.should eq "John"
      schema.email.should eq "john@example.com"
      schema.age.should eq 25
      schema.terms_accepted.should be_true
    end

    it "handles nested form data" do
      body = "user[name]=John&user[email]=john@example.com&user[address][street]=123 Main St&user[address][city]=NYC&tags[]=developer&tags[]=ruby"
      request = HTTP::Request.new("POST", "/profile")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(body)

      data = Amber::Schema::Parser::ParserRegistry.parse_request(request)

      # The form parser should correctly parse nested structures
      data["user"].as_h["name"].as_s.should eq "John"
      data["user"].as_h["email"].as_s.should eq "john@example.com"
      data["user"].as_h["address"].as_h["street"].as_s.should eq "123 Main St"
      data["user"].as_h["address"].as_h["city"].as_s.should eq "NYC"
      data["tags"].as_a.size.should eq 2
      data["tags"].as_a[0].as_s.should eq "developer"
      data["tags"].as_a[1].as_s.should eq "ruby"
    end

    it "validates array fields" do
      body = "tags[]=programming&tags[]=crystal&tags[]=web&categories[]=tech&categories[]=tutorial"
      request = HTTP::Request.new("POST", "/tags")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(body)

      data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      schema = TagsSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      tags = schema.tags.not_nil!
      tags.size.should eq 3
      tags.should contain "programming"
      tags.should contain "crystal"
      tags.should contain "web"
    end

    it "handles validation errors in form data" do
      # Submit invalid data
      body = "name=Jo&email=invalid-email&age=15"
      request = HTTP::Request.new("POST", "/strict")
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = IO::Memory.new(body)

      data = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      schema = StrictSchema.new(data)
      result = schema.validate

      result.success?.should be_false
      result.errors.size.should be >= 3

      # Check that we get appropriate error types
      error_codes = result.errors.map(&.code)
      error_codes.should contain "invalid_length"
      error_codes.should contain "invalid_format"
      error_codes.should contain "out_of_range"
    end
  end

  describe "File upload handling" do
    it "validates file upload constraints" do
      # Create mock file upload data as the parser would create it
      file_data = {
        "filename"     => JSON::Any.new("profile.jpg"),
        "content_type" => JSON::Any.new("image/jpeg"),
        "size"         => JSON::Any.new(500000_i64),
        "content"      => JSON::Any.new("fake image content"),
        "headers"      => JSON::Any.new({
          "Content-Type" => JSON::Any.new("image/jpeg"),
        } of String => JSON::Any),
      } of String => JSON::Any

      data = {
        "avatar" => JSON::Any.new(file_data),
        "name"   => JSON::Any.new("John Doe"),
      } of String => JSON::Any

      schema = FileUploadSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.name.should eq "John Doe"

      avatar = schema.avatar.not_nil!
      avatar["filename"].as_s.should eq "profile.jpg"
      avatar["content_type"].as_s.should eq "image/jpeg"
      avatar["size"].as_i64.should eq 500000
    end

    it "rejects files that are too large" do
      # Create file that's too large
      file_data = {
        "filename"     => JSON::Any.new("large_file.pdf"),
        "content_type" => JSON::Any.new("application/pdf"),
        "size"         => JSON::Any.new(200000_i64), # 200KB, exceeds 100KB limit
        "content"      => JSON::Any.new("fake pdf content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      data = {
        "document" => JSON::Any.new(file_data),
      } of String => JSON::Any

      schema = FileSizeSchema.new(data)
      result = schema.validate

      result.success?.should be_false
      result.errors.size.should eq 1
      result.errors[0].code.should eq "file_too_large"
    end

    it "rejects files with invalid content types" do
      file_data = {
        "filename"     => JSON::Any.new("document.pdf"),
        "content_type" => JSON::Any.new("application/pdf"),
        "size"         => JSON::Any.new(2000000_i64), # 2MB, exceeds 1MB limit
        "content"      => JSON::Any.new("fake pdf content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      data = {
        "image" => JSON::Any.new(file_data),
      } of String => JSON::Any

      schema = ImageOnlySchema.new(data)
      result = schema.validate

      result.success?.should be_false
      result.errors.size.should eq 1
      result.errors[0].code.should eq "file_too_large"
    end

    it "handles multiple file uploads" do
      file1_data = {
        "filename"     => JSON::Any.new("doc1.pdf"),
        "content_type" => JSON::Any.new("application/pdf"),
        "size"         => JSON::Any.new(1000_i64),
        "content"      => JSON::Any.new("pdf content 1"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      file2_data = {
        "filename"     => JSON::Any.new("doc2.pdf"),
        "content_type" => JSON::Any.new("application/pdf"),
        "size"         => JSON::Any.new(2000_i64),
        "content"      => JSON::Any.new("pdf content 2"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      data = {
        "attachments" => JSON::Any.new([
          JSON::Any.new(file1_data),
          JSON::Any.new(file2_data),
        ] of JSON::Any),
      } of String => JSON::Any

      schema = MultiFileSchema.new(data)
      result = schema.validate

      result.success?.should be_true

      attachments = schema.attachments.not_nil!
      attachments.size.should eq 2
      attachments[0]["filename"].as_s.should eq "doc1.pdf"
      attachments[1]["filename"].as_s.should eq "doc2.pdf"
    end
  end

  describe "Mixed form and file data" do
    it "handles forms with both regular fields and file uploads" do
      # Simulate a complex form with files
      featured_image_data = {
        "filename"     => JSON::Any.new("featured.jpg"),
        "content_type" => JSON::Any.new("image/jpeg"),
        "size"         => JSON::Any.new(150000_i64),
        "content"      => JSON::Any.new("image content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      attachment_data = {
        "filename"     => JSON::Any.new("extra.pdf"),
        "content_type" => JSON::Any.new("application/pdf"),
        "size"         => JSON::Any.new(50000_i64),
        "content"      => JSON::Any.new("pdf content"),
        "headers"      => JSON::Any.new({} of String => JSON::Any),
      } of String => JSON::Any

      data = {
        "title"          => JSON::Any.new("My Great Article"),
        "description"    => JSON::Any.new("This is an awesome article"),
        "category"       => JSON::Any.new("tech"),
        "featured_image" => JSON::Any.new(featured_image_data),
        "attachments"    => JSON::Any.new([JSON::Any.new(attachment_data)] of JSON::Any),
        "tags"           => JSON::Any.new([JSON::Any.new("crystal"), JSON::Any.new("programming")] of JSON::Any),
        "published"      => JSON::Any.new(true),
      } of String => JSON::Any

      schema = CompleteFormSchema.new(data)
      result = schema.validate

      result.success?.should be_true
      schema.title.should eq "My Great Article"
      schema.category.should eq "tech"
      schema.published.should be_true

      featured = schema.featured_image.not_nil!
      featured["filename"].as_s.should eq "featured.jpg"

      attachments = schema.attachments.not_nil!
      attachments.size.should eq 1
      attachments[0]["filename"].as_s.should eq "extra.pdf"

      tags = schema.tags.not_nil!
      tags.should contain "crystal"
      tags.should contain "programming"
    end
  end
end
