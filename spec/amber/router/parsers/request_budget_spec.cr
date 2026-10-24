require "../../../spec_helper"

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

private def upload_tempfile_count : Int32
  Dir.children(Dir.tempdir).count(&.starts_with?("amber-upload"))
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
      ::File.read(files["doc"].file.path).should eq "file body"
      files["doc"].delete_tempfile
    end
  end
end
