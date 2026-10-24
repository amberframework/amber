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
