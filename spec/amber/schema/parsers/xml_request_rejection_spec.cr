require "../../../spec_helper"

private def xml_request(content_type : String, body : String = %(<user><name>Amber</name></user>)) : HTTP::Request
  request = HTTP::Request.new("POST", "/test")
  request.headers["Content-Type"] = content_type
  request.body = IO::Memory.new(body)
  request
end

describe Amber::Schema::Parser::ParserRegistry do
  describe "XML request bodies" do
    {"application/xml", "text/xml", "application/xhtml+xml", "application/soap+xml", "Application/XML; charset=utf-8"}.each do |content_type|
      it "answers #{content_type} with 415 Unsupported Media Type" do
        error = expect_raises(Amber::Schema::UnsupportedMediaTypeError) do
          Amber::Schema::Parser::ParserRegistry.parse_request(xml_request(content_type))
        end

        error.http_status.should eq(415)
        error.code.should eq("unsupported_media_type")
      end
    end

    it "keeps an XML media type out of the parser registry" do
      Amber::Schema::Parser::ParserRegistry.get("application/xml").should be_nil
      Amber::Schema::Parser::ParserRegistry.get("text/xml").should be_nil
    end

    it "leaves an XML-looking body without a declared media type unparsed" do
      request = HTTP::Request.new("POST", "/test")
      request.body = IO::Memory.new(%(<user><name>Amber</name></user>))

      Amber::Schema::Parser::ParserRegistry.parse_request(request).should be_empty
    end

    it "uses a parser an application registers for an XML media type" do
      Amber::Schema::Parser::ParserRegistry.register_body_parser("application/xml") do |body|
        name = body.gets_to_end[/<name>([^<]*)<\/name>/, 1]? || ""
        {"name" => JSON::Any.new(name)}
      end

      result = Amber::Schema::Parser::ParserRegistry.parse_request(xml_request("application/xml; charset=utf-8"))
      result["name"].as_s.should eq("Amber")

      expect_raises(Amber::Schema::UnsupportedMediaTypeError) do
        Amber::Schema::Parser::ParserRegistry.parse_request(xml_request("text/xml"))
      end
    ensure
      Amber::Schema::Parser::ParserRegistry.request_body_parsers.delete("application/xml")
    end

    it "answers a failing registered parser with 400 invalid_request_body" do
      Amber::Schema::Parser::ParserRegistry.register_body_parser("application/xml") do |_body|
        raise ArgumentError.new("unclosed element")
      end

      error = expect_raises(Amber::Schema::RequestParseError, /unclosed element/) do
        Amber::Schema::Parser::ParserRegistry.parse_request(xml_request("application/xml"))
      end
      error.http_status.should eq(400)
      error.code.should eq("invalid_request_body")
    ensure
      Amber::Schema::Parser::ParserRegistry.request_body_parsers.delete("application/xml")
    end

    it "still parses a JSON body" do
      request = xml_request("application/json", %({"name":"Amber"}))

      Amber::Schema::Parser::ParserRegistry.parse_request(request)["name"].as_s.should eq("Amber")
    end
  end
end
