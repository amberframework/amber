require "../../../spec_helper"

describe HTTP::Server::Context do
  {% for request_method in HTTP::Server::Context::METHODS %}
  describe "{{request_method.id}}" do
    it "returns true when request matches {{request_method.id}}" do
      request = HTTP::Request.new("{{request_method.id}}", "/")
      context = create_context(request)
      context.{{request_method.id}}?.should eq true
    end

    it "returns false when request does not match {{request_method.id}}" do
       request = HTTP::Request.new("INVALID", "/")
       context = create_context(request)
       context.{{request_method.id}}?.should eq false
    end
  end
  {% end %}

  describe "#requested_url" do
    it "returns the url requested by the client" do
      url = "http://www.requested-url.com/hello"
      request = HTTP::Request.new("GET", url)
      context = create_context(request)
      context.requested_url.should eq url
    end
  end

  describe "port" do
    it "gets the port from the requested URL" do
      url = "http://localhost:9450"
      request = HTTP::Request.new("GET", url)
      context = create_context(request)
      context.port.should eq 9450
    end
  end

  describe "#format" do
    {html:  "text/html",
     xml:   "application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
     xhtml: "application/xhtml+xml",
     ics:   "text/calendar"}.each do |format, content_type|
      it "gets request format for #{content_type}" do
        headers = HTTP::Headers.new
        headers[Amber::Support::MimeTypes::FORMAT_HEADER] = content_type
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.format.should eq format.to_s
      end
    end

    %w(html json txt text xml).each do |format|
      it "get format #{format} from path extension" do
        request = HTTP::Request.new("GET", "/index.#{format}")
        context = create_context(request)
        context.format.should eq format.to_s
      end
    end
  end
end
