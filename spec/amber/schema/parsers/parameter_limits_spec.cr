require "../../../spec_helper"

private MAX_REJECTION_BYTES = 8_u64 * 1024 * 1024

private def parse_nested(query : String, config = Amber::Configuration::ParamsConfig.new) : Hash(String, JSON::Any)
  Amber::Schema::Parser::QueryParser.parse_params_to_nested(HTTP::Params.parse(query), config)
end

private def expect_rejected(query : String, limit_name : String, config = Amber::Configuration::ParamsConfig.new) : Nil
  allocated = bytes_allocated_by do
    error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
      parse_nested(query, config)
    end
    error.status_code.should eq 400
    error.limit_name.should eq limit_name
  end
  allocated.should be < MAX_REJECTION_BYTES
end

describe Amber::Schema::Parser::QueryParser do
  describe ".parse_params_to_nested limits" do
    it "keeps ordinary indexed parameters working" do
      result = parse_nested("items[1]=b&items[0]=a")
      result["items"].as_a.map(&.as_s).should eq ["a", "b"]
    end

    it "rejects items[999999999] with a 400 and bounded memory" do
      expect_rejected("items[999999999]=x", "max_array_index")
    end

    it "rejects an index that overflows Int64 with a 400" do
      expect_rejected("items[9999999999999999999999]=x", "max_array_index")
    end

    it "rejects a negative index with a 400" do
      expect_rejected("items[-1]=x", "max_array_index")
    end

    it "rejects a key nested deeper than max_nesting_depth" do
      key = "a" + "[b]" * 40
      expect_rejected("#{key}=x", "max_nesting_depth")
    end

    it "rejects more parameters than max_params" do
      query = (0..1_000).map { |i| "f#{i}=x" }.join("&")
      expect_rejected(query, "max_params")
    end

    it "bounds total array padding across one request" do
      query = (0..40).map { |i| "list#{i}[32]=x" }.join("&")
      expect_rejected(query, "max_array_padding")
    end
  end

  describe ".parse_request" do
    it "turns a limit violation into a 400 request parse error" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "items[999999999]=x")

      error = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      error.http_status.should eq 400
      error.code.should eq "parameter_limit_exceeded"
    end
  end
end

describe Amber::Schema::Parser::JSONParser do
  describe ".parse_params limits" do
    it "rejects a large bracket index without padding" do
      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /array indices/) do
          Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("items[999999999][name]=x"))
        end
      end
      allocated.should be < MAX_REJECTION_BYTES
    end

    it "rejects a nested index that overflows Int32" do
      expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
        Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("user[tags][9999999999]=x"))
      end
    end
  end
end

describe Amber::Schema::Parser::MultipartParser do
  describe ".parse_multipart_request limits" do
    it "rejects an indexed field name above max_array_index" do
      boundary = "AmberLimitBoundary"
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"items[999999999]\"\r\n\r\nx\r\n--#{boundary}--\r\n"
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /array indices/) do
          Amber::Schema::Parser::MultipartParser.parse_multipart_request(request)
        end
      end
      allocated.should be < MAX_REJECTION_BYTES
    end
  end
end

describe "schema parsers sharing one budget per request" do
  it "charges field and file padding against one max_array_padding" do
    boundary = "AmberLimitBoundary"
    body = String.build do |io|
      31.times do |i|
        io << "--#{boundary}\r\nContent-Disposition: form-data; name=\"a#{i}[32]\"\r\n\r\nx\r\n"
        io << "--#{boundary}\r\nContent-Disposition: form-data; name=\"f#{i}[32]\"; filename=\"f.txt\"\r\n\r\nx\r\n"
      end
      io << "--#{boundary}--\r\n"
    end
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)
    fields, files = Amber::Router::Parsers::Multipart.parse(request)

    error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
      Amber::Schema::Parser::MultipartParser.parse_router_params(fields, files)
    end
    error.limit_name.should eq "max_array_padding"
  end

  it "rejects an indexed upload's key before reading the file" do
    boundary = "IndexedUploadBoundary"
    payload = "f" * (4 * 1024 * 1024)
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"files[33]\"; filename=\"a.bin\"\r\n\r\n#{payload}\r\n--#{boundary}--\r\n"
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)

    allocated = bytes_allocated_by do
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_array_index_gap/) do
        Amber::Schema::Parser::MultipartParser.parse_multipart_request(request)
      end
    end
    allocated.should be < 1_u64 * 1024 * 1024
  end

  it "rejects a cached upload's key before reading its tempfile" do
    boundary = "IndexedUploadBoundary"
    payload = "f" * (4 * 1024 * 1024)
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"files[33]\"; filename=\"a.bin\"\r\n\r\n#{payload}\r\n--#{boundary}--\r\n"
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)
    files = request.params.files

    allocated = bytes_allocated_by do
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_array_index_gap/) do
        Amber::Schema::Parser::MultipartParser.parse_router_params(request.params.multipart_params, files, request.param_budget)
      end
    end
    allocated.should be < 1_u64 * 1024 * 1024
    request.delete_uploaded_files
  end

  it "bounds uploads the schema multipart parser reads into memory" do
    config = Amber::Configuration::ParamsConfig.new
    config.max_file_bytes = 1_024_i64
    boundary = "AmberLimitBoundary"
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"d.txt\"\r\n\r\n#{"x" * 4_096}\r\n--#{boundary}--\r\n"
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)

    expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_file_bytes/) do
      Amber::Schema::Parser::MultipartParser.parse_multipart_request(request, Amber::Router::Parsers::ParamBudget.new(config))
    end
  end
end

describe Amber::Schema::Parser::JSONParser do
  it "builds objects inside indexed arrays" do
    result = Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("items[1][name]=bob&items[0][name]=alice"))
    result["items"].as_a.map(&.["name"].as_s).should eq ["alice", "bob"]
  end

  it "builds [{\"name\" => \"alice\"}] from items[0][name]=alice" do
    result = Amber::Schema::Parser::JSONParser.parse_params(HTTP::Params.parse("items[0][name]=alice"))
    result["items"].should eq JSON.parse(%([{"name":"alice"}]))
  end

  it "counts and size-checks every element of an array value in parse_multipart" do
    config = Amber::Configuration::ParamsConfig.new
    config.max_params = 1
    params = {"tags[]" => ["x"] * 100} of String => String | Array(String)

    expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
      Amber::Schema::Parser::JSONParser.parse_multipart(params, config)
    end

    config = Amber::Configuration::ParamsConfig.new
    config.max_value_bytes = 4
    params = {"tags[]" => ["ok", "too long"]} of String => String | Array(String)
    expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
      Amber::Schema::Parser::JSONParser.parse_multipart(params, config)
    end
  end

  it "checks parse_query_string pair by pair as it decodes" do
    config = Amber::Configuration::ParamsConfig.new
    query = "a=1&" * 2_000_000

    allocated = bytes_allocated_by do
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        Amber::Schema::Parser::QueryParser.parse_query_string(query, config)
      end
    end
    allocated.should be < MAX_REJECTION_BYTES
  end
end

describe Amber::Schema::Parser::XMLParser do
  describe "extraction limits" do
    text_bytes = 7 * 1024 * 1024
    nested_xml = "#{"<a>" * 200}#{"x" * text_bytes}#{"</a>" * 200}"

    it "keeps base's descendant text in element#text within a bounded allocation" do
      text = "y" * 65_536
      xml = "<note>Hello <b>world</b> of XML#{"<a>" * 30}#{text}#{"</a>" * 30}</note>"
      result = {} of String => JSON::Any

      allocated = bytes_allocated_by do
        result = Amber::Schema::Parser::XMLParser.parse_string(xml)
      end

      result["note#text"].should eq JSON::Any.new("Hello world of XML#{text}")
      result["note.b"].should eq JSON::Any.new("world")
      result["note.a#text"].should eq JSON::Any.new(text)
      result[(["note"] + Array.new(30, "a")).join(".")].should eq JSON::Any.new(text)
      # The output itself holds 31 copies of the text; extraction allocates
      # at most a few times that.
      allocated.should be < 4_u64 * 31 * text.bytesize
    end

    it "rejects 200 nested elements around 7 MiB of text at the total extraction cap" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_nesting_depth = 1_024
      config.max_value_bytes = 8 * 1024 * 1024

      allocated = bytes_allocated_by do
        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          Amber::Schema::Parser::XMLParser.parse_string(nested_xml, config)
        end
        error.limit_name.should eq "max_document_body_bytes"
      end
      # Four ancestors' copies fit the 32 MiB cap before it trips; copying
      # the text at every ancestor would allocate more than 1.4 GB.
      allocated.should be < 8_u64 * text_bytes
    end

    it "rejects the same document under the default limits before copying its text" do
      allocated = bytes_allocated_by do
        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          Amber::Schema::Parser::XMLParser.parse_string(nested_xml)
        end
        error.limit_name.should eq "max_value_bytes"
      end
      allocated.should be < 3_u64 * text_bytes
    end

    it "checks max_value_bytes before building a value" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_value_bytes = 16
      config.max_document_body_bytes = 1_073_741_824
      text = "x" * (4 * 1024 * 1024)
      root = XML.parse("<root>#{text}<b/></root>").first_element_child || raise "no root element"
      allowance = Amber::Schema::Parser::XMLParser::ExtractionAllowance.new(config)

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          allowance.text_of(root)
        end
      end
      # Measuring reads the text node once; building the value would copy it again.
      allocated.should be < (text.bytesize + text.bytesize // 2).to_u64
    end

    it "checks XPath values against max_value_bytes and the total cap" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_document_body_bytes = 1_024
      allowance = Amber::Schema::Parser::XMLParser::ExtractionAllowance.new(config)
      node = XML.parse("<a>#{"x" * 3_000}</a>").first_element_child || raise "no root element"

      Amber::Schema::Parser::XMLParser.extract_node_value(node, allowance).as_s.bytesize.should eq 3_000
      error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
        Amber::Schema::Parser::XMLParser.extract_node_value(node, allowance)
      end
      error.limit_name.should eq "max_document_body_bytes"

      value_config = Amber::Configuration::ParamsConfig.new
      value_config.max_value_bytes = 1_048_576
      title = XML.parse("<title>#{"t" * 1_048_577}</title>").first_element_child || raise "no root element"
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
        Amber::Schema::Parser::XMLParser.extract_node_value(title, Amber::Schema::Parser::XMLParser::ExtractionAllowance.new(value_config))
      end
    end

    it "rejects an extracted value larger than max_value_bytes" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_value_bytes = 8
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
        Amber::Schema::Parser::XMLParser.parse_string("<note>#{"x" * 9}</note>", config)
      end
    end

    it "copies stripped text once, charging what it keeps" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_value_bytes = 8 * 1024 * 1024
      text = "x" * (2 * 1024 * 1024)
      xml = "#{"<a>" * 4}  #{text}  #{"</a>" * 4}"
      result = {} of String => JSON::Any

      allocated = bytes_allocated_by do
        result = Amber::Schema::Parser::XMLParser.parse_string(xml, config)
      end

      result["a#text"].as_s.bytesize.should eq text.bytesize
      result["a.a.a.a"].as_s.bytesize.should eq text.bytesize
      # Four kept values plus one cached read of the text node and the parse;
      # stripping each value after building it would add four more copies.
      allocated.should be < 8_u64 * text.bytesize
    end

    it "rejects a document with more than max_document_nodes nodes before extracting" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_document_nodes = 1_000
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_nodes/) do
        Amber::Schema::Parser::XMLParser.parse_string("<r>#{"<a/>" * 1_000}</r>", config)
      end
      Amber::Schema::Parser::XMLParser.parse_string("<r>#{"<a/>" * 998}</r>", config).should_not be_empty
    end

    it "counts a well-formed document's nodes while it streams, before building its tree" do
      xml = "<r>#{"<a/>" * 1_000_000}</r>"
      # The streaming count stops one node past the limit; libxml's tree is
      # outside the garbage collector, so this shows it is never needed.
      Amber::Schema::Parser::XMLParser.streamed_node_count(xml, 100_000).should eq 100_001
      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_nodes/) do
          Amber::Schema::Parser::XMLParser.parse_string(xml)
        end
      end
      allocated.should be < 4_u64 * 1024 * 1024
    end

    it "counts a recovered malformed document's tree before extracting" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_document_nodes = 1_000
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_nodes/) do
        Amber::Schema::Parser::XMLParser.parse_string("<r><a></b>#{"<a/>" * 2_000}</r>", config)
      end
    end

    it "measures text and attribute values in place before copying them" do
      text = "x" * (7 * 1024 * 1024)
      root = XML.parse("<r v=\"#{text}\">#{text}</r>").first_element_child || raise "no root element"
      allowance = Amber::Schema::Parser::XMLParser::ExtractionAllowance.new
      attribute = root.attributes.first? || raise "no attribute"

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          allowance.text_of(root)
        end
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          allowance.attribute_value(attribute)
        end
      end
      allocated.should be < 256_u64 * 1024
    end

    it "strips multibyte whitespace the way String#strip does" do
      result = Amber::Schema::Parser::XMLParser.parse_string("<p>\u3000\u2003value \u00A0x\u2029\u3000<b/></p>")
      result["p#text"].should eq JSON::Any.new("value \u00A0x")
    end

    it "rejects a document type declaration, so no entity is expanded or counted" do
      {
        %(<!DOCTYPE r [<!ENTITY x "#{"y" * 1_024}">]><r a="&x;&x;&x;">&x;</r>),
        # The comment is malformed, so the streaming count stops before the
        # DOCTYPE; the recovered tree is checked instead.
        %(<!-- a -- b --><!DOCTYPE r [<!ENTITY x "y">]><r>&x;</r>),
      }.each do |xml|
        expect_raises(Amber::Exceptions::BadRequest, /document type declaration/) do
          Amber::Schema::Parser::XMLParser.parse_string(xml)
        end
      end
    end

    it "answers a DOCTYPE in a request body as a 400 request parse error" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/xml"}, %(<!DOCTYPE r [<!ENTITY x "y">]><r>&x;</r>))
      error = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      error.http_status.should eq 400
    end

    it "keeps a rejection raised after the body was read" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_document_nodes = 1
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/xml"}, "<r><a/></r>")
      request.param_budget = Amber::Router::Parsers::ParamBudget.new(config)

      first = expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_document_nodes/) do
        Amber::Schema::Parser::XMLParser.parse_request(request)
      end
      second = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
        Amber::Schema::Parser::XMLParser.parse_request(request)
      end
      second.should be(first)
    end

    it "keeps a CBOR decoding rejection for later parses" do
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/cbor"}, Bytes[0xFF, 0x00])
      first = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      second = expect_raises(Amber::Schema::RequestParseError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(request)
      end
      second.should be(first)
    end

    it "checks the generated element#text key against max_key_bytes" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_key_bytes = 8
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_key_bytes/) do
        Amber::Schema::Parser::XMLParser.parse_string("<abcde>text<b/></abcde>", config)
      end
    end

    it "measures whitespace the way strip removes it" do
      result = Amber::Schema::Parser::XMLParser.parse_string("<p>\n  \u00A0value\u00A0 \n<b/></p>")
      result["p#text"].should eq JSON::Any.new("value")
    end
  end
end
