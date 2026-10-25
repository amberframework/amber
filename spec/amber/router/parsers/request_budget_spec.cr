require "../../../spec_helper"
require "file_utils"

private MAX_REJECTION_BYTES = 8_u64 * 1024 * 1024

private def limits_with(&) : Amber::Configuration::ParamsConfig
  config = Amber::Configuration::ParamsConfig.new
  yield config
  config
end

private def multipart_body(boundary : String, list_of_parts : Array(Tuple(String, String?, String)), epilogue : String = "") : String
  String.build do |io|
    list_of_parts.each do |name, filename, content|
      io << "--" << boundary << "\r\n"
      io << %(Content-Disposition: form-data; name="#{name}")
      io << %(; filename="#{filename}") if filename
      io << "\r\n\r\n" << content << "\r\n"
    end
    io << "--" << boundary << "--\r\n" << epilogue
  end
end

private def multipart_post(body : String, boundary : String = "AmberBudgetBoundary") : HTTP::Request
  HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)
end

# Reads *first*, then makes *directory* read-only, then reads *rest*.
private class LockingIO < IO
  @locked = false

  def initialize(@first : IO, @rest : IO, @directory : String)
  end

  def read(slice : Bytes) : Int32
    count = @first.read(slice)
    return count if count > 0

    unless @locked
      ::File.chmod(@directory, 0o500)
      @locked = true
    end
    @rest.read(slice)
  end

  def write(slice : Bytes) : Nil
    raise IO::Error.new("read only")
  end
end

private class RequestBudgetSchema < Amber::Schema::Definition
  field :title, String
end

private def upload_tempfile_count : Int32
  Dir.children(Amber::Router::File.upload_directory).count(&.starts_with?("amber-upload"))
end

module Amber::Router::Parsers
  describe "HTTP::Request#query_params" do
    it "rejects an oversized query on every access, including after a caught error" do
      query = Array.new(1_001, "a=1").join("&")
      request = HTTP::Request.new("GET", "/?#{query}")

      2.times do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
          request.query_params
        end
      end
    end

    it "bounds the schema query path that reads query_params directly" do
      query = Array.new(1_001, "a=1").join("&")
      # A media type registered to the query parser reads `query_params`.
      Amber::Schema::Parser::ParserRegistry.register("application/x-amber-query-test", "query")
      request = HTTP::Request.new("GET", "/?#{query}", HTTP::Headers{"Content-Type" => "application/x-amber-query-test"})

      error = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      error.code.should eq "parameter_limit_exceeded"
    end

    it "parses an ordinary query once" do
      request = HTTP::Request.new("GET", "/?a=1&b=2")
      request.query_params["b"].should eq "2"
      request.query_params["a"].should eq "1"
      request.param_budget.param_count.should eq 2
    end
  end

  describe "one budget per request" do
    it "counts query pairs and form fields together" do
      request = HTTP::Request.new("POST", "/?q1=1&q2=2", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a=1&b=2")
      request.param_budget = ParamBudget.new(limits_with(&.max_params = 3))

      request.query_params.size.should eq 2
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        request.params.form_params
      end
    end

    it "charges router-cached fields once during schema conversion" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a=1&b=2")
      request.param_budget = ParamBudget.new(limits_with(&.max_params = 2))

      request.params.form_params.size.should eq 2
      result = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      result.keys.should eq ["a", "b"]
    end

    it "shares array padding between routing and schema conversion" do
      fields = Array.new(31) { |i| "a#{i}[32]=x" }.join("&")
      request = HTTP::Request.new("POST", "/?#{Array.new(2) { |i| "q#{i}[32]=x" }.join("&")}", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, fields)

      request.params.form_params
      Amber::Schema::Parser::ParserRegistry.parse_request(request)
      request.param_budget.padding_used.should eq 31 * 32
    end
  end

  describe "URL-encoded reads" do
    it "never reads past the remaining body allowance" do
      config = limits_with(&.max_form_body_bytes = 10)
      body = "a=" + "x" * 2_097_152

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
          ParamBudget.new(config).parse_form(IO::Memory.new(body))
        end
      end
      allocated.should be < 1_048_576_u64
    end

    it "rejects an oversized encoded key before decoding it" do
      config = limits_with(&.max_key_bytes = 16)
      body = "#{"%41" * 100}=x"

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_key_bytes/) do
        ParamBudget.new(config).parse_form(IO::Memory.new(body))
      end
    end

    it "decodes like URI::Params, including ; separators and + as space" do
      params = ParamBudget.new(Amber::Configuration::ParamsConfig.new).parse_form(IO::Memory.new("a=1+2;b=%41&flag&&c="))
      params.to_s.should eq HTTP::Params.parse("a=1+2;b=%41&flag&&c=").to_s
    end
  end

  describe "key depth" do
    it "rejects a deep key without splitting it" do
      config = limits_with(&.max_key_bytes = 1_048_576)
      key = "a" + "[b]" * 100_000
      params = {key => "x"}

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_nesting_depth/) do
          Amber::Schema::Parser::QueryParser.parse_params_to_nested(params, config)
        end
      end
      allocated.should be < 1_048_576_u64
    end
  end

  describe Multipart do
    it "rejects an oversized part header while reading it" do
      config = limits_with(&.max_part_header_bytes = 1_024)
      body = multipart_body("AmberBudgetBoundary", [{"a" * 10_000_000, nil, "x"}])
      request = multipart_post(body)

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_part_header_bytes/) do
          Multipart.parse(request, ParamBudget.new(config))
        end
      end
      allocated.should be < 1_048_576_u64
    end

    it "counts an epilogue after the closing boundary toward the body cap" do
      config = limits_with(&.max_multipart_body_bytes = 1_024_i64)
      body = multipart_body("AmberBudgetBoundary", [{"note", nil, "x"}], epilogue: "y" * 4_096)

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_multipart_body_bytes/) do
        Multipart.parse(multipart_post(body), ParamBudget.new(config))
      end
    end

    it "removes earlier upload tempfiles when a later part is rejected" do
      config = limits_with(&.max_params = 1)
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "x"}, {"note", nil, "y"}])
      before = upload_tempfile_count

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        Multipart.parse(multipart_post(body), ParamBudget.new(config))
      end
      upload_tempfile_count.should eq before
    end

    it "parses an ordinary multipart body with a file and a field" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}, {"note", nil, "hello"}])
      fields, files = Multipart.parse(multipart_post(body), ParamBudget.new(Amber::Configuration::ParamsConfig.new))

      fields["note"].should eq "hello"
      ::File.read(files["doc"].path).should eq "file body"
      files["doc"].delete_tempfile
    end

    it "removes the tempfile of an upload replaced by a later part with the same name" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "first.txt", "first"}, {"doc", "second.txt", "second"}])
      before = upload_tempfile_count

      _fields, files = Multipart.parse(multipart_post(body), ParamBudget.new(Amber::Configuration::ParamsConfig.new))

      files.size.should eq 1
      ::File.read(files["doc"].path).should eq "second"
      upload_tempfile_count.should eq before + 1
      files["doc"].delete_tempfile
      upload_tempfile_count.should eq before
    end

    it "removes every tempfile, duplicates included, when a later part is rejected" do
      config = limits_with(&.max_params = 3)
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "1"}, {"doc", "b.txt", "2"}, {"doc", "c.txt", "3"}, {"note", nil, "x"}])
      before = upload_tempfile_count

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        Multipart.parse(multipart_post(body), ParamBudget.new(config))
      end
      upload_tempfile_count.should eq before
    end

    it "reports the bytes received, not the client's declared size" do
      boundary = "AmberBudgetBoundary"
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.txt\"; size=1\r\n\r\n#{"x" * 4_096}\r\n--#{boundary}--\r\n"
      fields, files = Multipart.parse(multipart_post(body, boundary), ParamBudget.new(Amber::Configuration::ParamsConfig.new))

      files["doc"].size.should eq 4_096
      schema_data = Amber::Schema::Parser::MultipartParser.parse_router_params(fields, files)
      schema_data["doc"]["size"].as_i64.should eq 4_096
      files["doc"].delete_tempfile
    end

    it "answers malformed part metadata with a bad request" do
      boundary = "AmberBudgetBoundary"
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"x\"; size=bogus\r\n\r\nx\r\n--#{boundary}--\r\n"

      error = expect_raises(Amber::Exceptions::BadRequest, /malformed/) do
        Multipart.parse(multipart_post(body, boundary), ParamBudget.new(Amber::Configuration::ParamsConfig.new))
      end
      error.status_code.should eq 400
    end
  end

  describe "multipart rejection cleanup" do
    it "keeps the limit error when deleting the tempfiles fails" do
      boundary = "AmberBudgetBoundary"
      body = multipart_body(boundary, [{"a", "a.txt", "first"}, {"b", "b.txt", "second"}, {"note", nil, "x" * 64}])
      directory = Amber::Router::File.upload_directory
      before = Dir.children(directory).to_set
      # Make the directory read-only once both files are written, so every
      # cleanup delete fails while the oversized field is rejected.
      trigger = body.index!("name=\"note\"")
      source = IO::Memory.new(body)
      reader = IO::Sized.new(source, trigger)
      rest = IO::Memory.new(body.byte_slice(trigger))
      locking = LockingIO.new(reader, rest, directory)
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"})
      request.body = locking

      begin
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          Multipart.parse(request, ParamBudget.new(limits_with(&.max_value_bytes = 8)))
        end
      ensure
        ::File.chmod(directory, 0o700)
      end

      (Dir.children(directory).to_set - before).size.should eq 2

      # The request retries the cleanup when it finishes.
      request.delete_uploaded_files
      (Dir.children(directory).to_set - before).should be_empty
    end
  end

  describe "an upload rejected while its directory cannot be written" do
    it "keeps the limit error and deletes the tempfile when the request finishes" do
      boundary = "AmberBudgetBoundary"
      body = multipart_body(boundary, [{"doc", "a.bin", "z" * 131_072}])
      directory = Amber::Router::File.upload_directory
      before = Dir.children(directory).to_set
      # Lock the directory once the part's headers are read and its tempfile
      # exists, so deleting the over-limit tempfile fails.
      trigger = body.index!("\r\n\r\n") + 4 + 40_000
      locking = LockingIO.new(IO::Sized.new(IO::Memory.new(body), trigger), IO::Memory.new(body.byte_slice(trigger)), directory)
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"})
      request.body = locking

      begin
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_file_bytes/) do
          Multipart.parse(request, ParamBudget.new(limits_with(&.max_file_bytes = 65_536_i64)))
        end
      ensure
        ::File.chmod(directory, 0o700)
      end
      (Dir.children(directory).to_set - before).size.should eq 1

      request.delete_uploaded_files
      (Dir.children(directory).to_set - before).should be_empty
    end
  end

  describe "an upload whose deletion fails when the request finishes" do
    it "is deleted by a later request once the directory is writable again" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}])
      directory = Amber::Router::File.upload_directory
      before = Dir.children(directory).to_set
      request = multipart_post(body)
      request.params.files["doc"].path.should_not be_empty

      ::File.chmod(directory, 0o500)
      begin
        request.delete_uploaded_files
      ensure
        ::File.chmod(directory, 0o700)
      end
      (Dir.children(directory).to_set - before).size.should eq 1

      HTTP::Request.new("GET", "/").delete_uploaded_files
      (Dir.children(directory).to_set - before).should be_empty
    end
  end

  describe "an upload moved across file systems whose original cannot be deleted" do
    it "is deleted by a later request once the directory is writable again" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}])
      directory = Amber::Router::File.upload_directory
      before = Dir.children(directory).to_set
      request = multipart_post(body)
      upload = request.params.files["doc"]
      target_directory = ::File.tempname("amber-move-target")
      Dir.mkdir(target_directory)
      target = ::File.join(target_directory, "kept.txt")
      across_file_systems = ->(from : String, to : String) do
        raise ::File::Error.from_os_error("Error renaming file", Errno::EXDEV, file: from, other: to)
      end

      ::File.chmod(directory, 0o500)
      begin
        upload.move_to(target, across_file_systems).should eq target
        request.delete_uploaded_files
      ensure
        ::File.chmod(directory, 0o700)
      end
      ::File.read(target).should eq "file body"
      (Dir.children(directory).to_set - before).size.should eq 1

      HTTP::Request.new("GET", "/").delete_uploaded_files
      (Dir.children(directory).to_set - before).should be_empty
      ::File.read(target).should eq "file body"
      FileUtils.rm_rf(target_directory)
    end
  end

  describe "repeated schema parses" do
    it "charge the request's array padding once" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a[32]=x")
      request.param_budget = ParamBudget.new(limits_with(&.max_array_padding = 32))

      first = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      second = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      second.should eq first
      first["a"].as_a.size.should eq 33
    end
  end

  describe "form charsets" do
    it "decodes a declared charset while the form streams" do
      body = "title=caf".to_slice + Bytes[0xE9]
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded; charset=ISO-8859-1"}, body)
      request.form_params["title"]?.should eq "café"
    end

    it "decodes a UTF-16 form" do
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded; charset=UTF-16LE"}, "title=ok".encode("UTF-16LE"))
      request.form_params["title"]?.should eq "ok"
    end

    it "counts the raw bytes of a form in a charset that shrinks when decoded" do
      body = "a=#{"x" * 40}".encode("UTF-16LE")
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded; charset=UTF-16LE"}, body)
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
        FormData.parse(request, ParamBudget.new(limits_with(&.max_form_body_bytes = 64)))
      end
    end

    it "leaves the declared charset out of the error message" do
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => %(application/x-www-form-urlencoded; charset="<script>alert(1)</script>")}, "title=x")
      error = expect_raises(Amber::Exceptions::BadRequest, /declared charset/) { request.form_params }
      error.message.to_s.should_not contain("script")
    end

    it "answers an unknown charset with a bad request" do
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded; charset=no-such-charset"}, "title=x")
      expect_raises(Amber::Exceptions::BadRequest, /could not be decoded/) { request.form_params }
    end
  end

  describe "a rejected body" do
    it "is not served from the router's cached form after a schema contract rejects it" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a[33]=x")
      request.params.form_params["a[33]"]?.should eq "x"

      expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      expect_raises(Amber::Schema::RequestParseError) { request.form_params? }
      expect_raises(Amber::Schema::RequestParseError) { request.params["a[33]"]? }
    end

    it "raises the same schema error on a repeated parse" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, %({"title":"seventeen"}))
      request.param_budget = ParamBudget.new(limits_with(&.max_document_body_bytes = 16))

      first = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      second = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      second.should be(first)
    end

    it "stays rejected for params after a schema read rejects it" do
      body = "#{" " * 70_000}{\"role\":\"admin\"}"
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, body)
      request.param_budget = ParamBudget.new(limits_with(&.max_document_body_bytes = 16))

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Schema::Parser::JSONParser.parse_request(request)
      end
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        request.params["role"]?
      end
    end
  end

  describe "cached schema data" do
    it "rejects an unsupported media type for a schema after a plain parse cached the body" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/octet-stream"}, "{}")
      Amber::Schema::Parser::ParserRegistry.parse_request(request).should be_empty

      expect_raises(Amber::Schema::UnsupportedMediaTypeError, /application\/octet-stream/) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request, RequestBudgetSchema)
      end
    end

    it "keeps rejecting a malformed JSON body on a later schema parse" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, "{")
      first = expect_raises(Amber::Schema::RequestParseError, /Invalid JSON/) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request, RequestBudgetSchema)
      end
      first.code.should eq "invalid_request_body"
      second = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request, RequestBudgetSchema)
      end
      second.should be(first)
    end

    it "gives each parse its own copy of nested values" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, %({"a":{"b":[1]}}))
      first = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      first["a"].as_h["c"] = ::JSON::Any.new(2_i64)
      first["a"].as_h["b"].as_a << ::JSON::Any.new(3_i64)

      second = Amber::Schema::Parser::ParserRegistry.parse_request(request)
      second["a"].as_h.has_key?("c").should be_false
      second["a"].as_h["b"].as_a.size.should eq 1
    end
  end

  describe "CBOR and COSE bodies" do
    it "rejects a CBOR body over max_document_body_bytes" do
      body = Amber::Schema::CBOR.encode({"title" => ::JSON::Any.new("x" * 40)})
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/cbor"}, body)
      request.param_budget = ParamBudget.new(limits_with(&.max_document_body_bytes = 16))

      error = expect_raises(Amber::Schema::RequestParseError, /max_document_body_bytes/) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      error.code.should eq "parameter_limit_exceeded"
    end

    it "rejects a declared CBOR length past max_document_body_bytes before allocating it" do
      # A one-entry map whose text value declares 1,048,568 bytes and sends none.
      body = Bytes[0xA1, 0x61, 0x61, 0x7A, 0x00, 0x0F, 0xFF, 0xF8]
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/cbor"}, body)
      request.param_budget = ParamBudget.new(limits_with(&.max_document_body_bytes = 16))

      allocated_before = GC.stats.total_bytes
      error = expect_raises(Amber::Schema::RequestParseError, /max_document_body_bytes/) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      (GC.stats.total_bytes - allocated_before).should be < 262_144
      error.code.should eq "parameter_limit_exceeded"
    end

    it "allocates a long declared CBOR value only as its bytes arrive" do
      body = Bytes[0xA1, 0x61, 0x61, 0x7A, 0x00, 0x0F, 0xFF, 0xF8]
      allocated_before = GC.stats.total_bytes
      expect_raises(Amber::Schema::CBOR::DecodeError, /unexpected end of input/) do
        Amber::Schema::CBOR.decode_object(IO::Memory.new(body))
      end
      (GC.stats.total_bytes - allocated_before).should be < 262_144
    end

    it "reports a COSE body over max_document_body_bytes as a limit error" do
      provider = Amber::Schema::COSE::KeyProvider.new(Bytes.new(32, 7_u8), "primary")
      encrypted = Amber::Schema::COSE.encrypt0(Amber::Schema::CBOR.encode({"title" => ::JSON::Any.new("x" * 40)}), provider)
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Schema::COSE.decrypt0(IO::Memory.new(encrypted), provider, max_document_body_bytes: 16)
      end
    end

    it "reports a declared CBOR length past both caps as a request limit error" do
      # A text value declaring 2 MiB, past the decoder's own 1 MiB text cap.
      body = Bytes[0xA1, 0x61, 0x61, 0x7A, 0x00, 0x20, 0x00, 0x00]
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Schema::CBOR.decode_object(IO::Memory.new(body), 16)
      end
    end

    it "reports a trailing byte past max_document_body_bytes as a request limit error" do
      document = Amber::Schema::CBOR.encode({"t" => ::JSON::Any.new("x")})
      body = IO::Memory.new
      body.write(document)
      body.write_byte(0x00)
      body.rewind
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Schema::CBOR.decode_object(body, document.size)
      end
    end

    it "grows CBOR arrays as elements arrive rather than from declared counts" do
      body = IO::Memory.new
      body.write(Bytes[0xA1, 0x61, 0x61])
      # 32 nested arrays, each declaring 16,384 elements.
      32.times { body.write(Bytes[0x99, 0x40, 0x00]) }
      body.rewind

      allocated_before = GC.stats.total_bytes
      expect_raises(Amber::Schema::CBOR::DecodeError) do
        Amber::Schema::CBOR.decode_object(body)
      end
      (GC.stats.total_bytes - allocated_before).should be < 262_144
    end

    it "reports the largest declared CBOR length as a request limit error" do
      body = Bytes[0xA1, 0x61, 0x61, 0x7B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Schema::CBOR.decode_object(IO::Memory.new(body), 16)
      end
    end

    it "reports a CBOR body that ends early as ending early, even at the limit" do
      expect_raises(Amber::Schema::CBOR::DecodeError, /unexpected end of input/) do
        Amber::Schema::CBOR.decode_object(IO::Memory.new(Bytes[0x18]), 1)
      end
    end

    it "reads a long CBOR value that arrives in full" do
      title = "t" * 200_000
      decoded = Amber::Schema::CBOR.decode_object(IO::Memory.new(Amber::Schema::CBOR.encode({"title" => ::JSON::Any.new(title)})))
      decoded["title"].as_s.should eq title
    end
  end

  describe "the development exception page" do
    it "renders a rejected query's error without reading the query again" do
      request = HTTP::Request.new("GET", "/?#{"a=1&" * 1_001}")
      context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
      error = expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) { request.query_params }

      page = Amber::Exceptions::Page.new(context, error).to_s
      page.should contain("max_params")
    end
  end

  describe Amber::Router::File do
    it "deletes every upload even when closing one handle fails" do
      body = multipart_body("AmberBudgetBoundary", [{"a", "a.txt", "first"}, {"b", "b.txt", "second"}])
      request = multipart_post(body)
      files = request.params.files
      handle = files["a"].file
      # Closing the descriptor underneath makes the handle's own close fail.
      LibC.close(handle.fd)

      request.delete_uploaded_files

      ::File.exists?(files["a"].path).should be_false
      ::File.exists?(files["b"].path).should be_false
    end

    it "holds no open handle until the action calls file" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}])
      _fields, files = Multipart.parse(multipart_post(body), ParamBudget.new(Amber::Configuration::ParamsConfig.new))

      files["doc"].open_tempfile(&.gets_to_end).should eq "file body"
      handle = files["doc"].file
      handle.gets_to_end.should eq "file body"
      files["doc"].delete_tempfile
      handle.closed?.should be_true
    end

    it "refuses to read a tempfile whose path now names another file" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}])
      _fields, files = Multipart.parse(multipart_post(body), ParamBudget.new(Amber::Configuration::ParamsConfig.new))
      path = files["doc"].path
      # Written while the tempfile still exists, so it has its own inode.
      replacement = "#{path}.replacement"
      ::File.write(replacement, "replacement")
      ::File.rename(replacement, path)

      expect_raises(IO::Error, /replaced/) do
        files["doc"].open_tempfile(&.gets_to_end)
      end
      ::File.delete(path)
    end
  end

  describe FormScanner do
    it "treats ; as a separator, so max_params applies to a body of a=1; pairs" do
      body = "a=1;" * 2_000_000

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
          ParamBudget.new(Amber::Configuration::ParamsConfig.new).parse_form(IO::Memory.new(body))
        end
      end
      allocated.should be < 1_048_576_u64
    end

    it "rejects a raw value while its bytes arrive" do
      config = limits_with(&.max_value_bytes = 1_024)
      body = "a=" + "x" * 10_000_000

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          ParamBudget.new(config).parse_form(IO::Memory.new(body))
        end
      end
      allocated.should be < 1_048_576_u64
    end

    it "matches URI::Params.parse on edge cases" do
      list_of_inputs = ["", "&", ";;", "a", "a=", "=b", "a==b", "a=1&a=2", "a+b=c+d", "%41%42=%7e", "%zz=%", "k=v;k2=v2&&k3"]
      list_of_inputs.each do |input|
        scanned = [] of Tuple(String, String)
        FormScanner.new(IO::Memory.new(input), Amber::Configuration::ParamsConfig.new).each_pair { |key, value| scanned << {key, value} }
        expected = [] of Tuple(String, String)
        URI::Params.parse(input) { |key, value| expected << {key, value} }
        scanned.should eq expected
      end
    end
  end

  describe "plain field names" do
    it "accepts a plain field named -1 and still rejects a bracketed negative index" do
      Amber::Schema::Parser::QueryParser.parse_params_to_nested({"-1" => "foo"})["-1"].as_s.should eq "foo"
      Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("-1=foo"))["-1"].as_s.should eq "foo"

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /array indices/) do
        Amber::Schema::Parser::QueryParser.parse_params_to_nested({"items[-1]" => "foo"})
      end
    end
  end

  describe "raw request target" do
    it "checks the query in the request target before the URI is parsed" do
      target = "/?" + "a=1&" * 2_000_000
      request = HTTP::Request.new("GET", target)

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
          request.query_params
        end
      end
      allocated.should be < 1_048_576_u64
    end

    it "stops the query at a fragment and reads an app-set query" do
      request = HTTP::Request.new("GET", "/?a=1#b=2")
      request.query_params.to_h.should eq({"a" => "1"})

      request = HTTP::Request.new("GET", "/")
      request.query = "c=3"
      request.query_params["c"].should eq "3"
    end

    it "leaves a file that replaced the tempfile's path during cleanup" do
      body = multipart_body("AmberBudgetBoundary", [{"doc", "a.txt", "file body"}])
      _fields, files = Multipart.parse(multipart_post(body), ParamBudget.new(Amber::Configuration::ParamsConfig.new))
      path = files["doc"].path
      ::File.delete(path)
      ::File.write(path, "replacement")

      files["doc"].delete_tempfile
      ::File.read(path).should eq "replacement"
      ::File.delete(path)
    end

    it "keeps uploads in a directory closed to other users" do
      info = ::File.info(Amber::Router::File.upload_directory, follow_symlinks: false)
      info.directory?.should be_true
      (info.permissions.value & 0o077).should eq 0
    end
  end

  describe "document bodies" do
    it "rejects a JSON body one byte over max_document_body_bytes" do
      config = limits_with(&.max_document_body_bytes = 16)
      fits = %({"a":"12345678"})
      fits.bytesize.should eq 16

      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, fits)
      request.param_budget = ParamBudget.new(config)
      Amber::Schema::Parser::ParserRegistry.parse_request(request)["a"].as_s.should eq "12345678"

      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, %({"a":"123456789"}))
      request.param_budget = ParamBudget.new(config)
      error = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      error.http_status.should eq 400
      error.code.should eq "parameter_limit_exceeded"
    end

    it "bounds the router's JSON params read" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, %({"a":"#{"x" * 100}"}))
      request.param_budget = ParamBudget.new(limits_with(&.max_document_body_bytes = 16))

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_body_bytes/) do
        Amber::Router::Parsers::JSON.parse(request)
      end
    end
  end

  describe "array-form keys in the JSON schema helpers" do
    it "checks depth and bracketed indices before collecting array values" do
      deep_key = "a" + "[b]" * 40 + "[]"

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_nesting_depth/) do
        Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("#{deep_key}=x"))
      end
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_nesting_depth/) do
        Amber::Schema::Parser::JSONParser.parse_multipart({deep_key => ["x"]} of String => String | Array(String))
      end
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /array indices/) do
        Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("tags[-1][]=x"))
      end
      Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("tags[]=a&tags[]=b"))["tags"].as_a.map(&.as_s).should eq ["a", "b"]
    end
  end
end
