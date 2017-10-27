require "../../../spec_helper"

describe HTTP::Server::Context do
  describe "#override_request_method!" do
    context "when X-HTTP-Method-Override is present" do
      it "overrides form POST method to PUT, PATCH, DELETE" do
        %w(PUT PATCH DELETE).each do |method|
          header = HTTP::Headers.new
          header[HTTP::Server::Context::OVERRIDE_HEADER] = method
          request = HTTP::Request.new("POST", "/?test=test", header)

          context = create_context(request)

          context.request.method.should eq method
        end
      end

      it "overrides form GET method to PUT, PATCH, DELETE" do
        %w(PUT PATCH DELETE).each do |method|
          header = HTTP::Headers.new
          header[HTTP::Server::Context::OVERRIDE_HEADER] = method
          request = HTTP::Request.new("GET", "/?test=test", header)

          context = create_context(request)

          context.request.method.should eq method
        end
      end

      it "takes form post over header override" do
        %w(PUT PATCH DELETE).each do |method|
          header = HTTP::Headers.new
          header[HTTP::Server::Context::OVERRIDE_HEADER] = method
          header["content-type"] = "application/x-www-form-urlencoded"
          request = HTTP::Request.new("GET", "/?test=test", header, "_method=PATCH")

          context = create_context(request)

          context.request.method.should eq "PATCH"
        end
      end

      it "overrides form request method only by upper case value" do
        header = HTTP::Headers.new
        header["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("GET", "/?test=test", header, "_method=put")

        context = create_context(request)
        context.request.method.should eq "PUT"
      end
    end

    it "overrides form POST method to PUT, PATCH, DELETE" do
      %w(PUT PATCH DELETE).each do |method|
        header = HTTP::Headers.new
        header["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("POST", "/?test=test", header, "_method=#{method}")

        context = create_context(request)

        context.request.method.should eq method
      end
    end

    it "overrides form GET method to PUT, PATCH, DELETE" do
      %w(PUT PATCH DELETE).each do |method|
        header = HTTP::Headers.new
        header["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("GET", "/?test=test", header, "_method=#{method}")

        context = create_context(request)

        context.request.method.should eq method
      end
    end

    it "does not override other than PUT, PATCH, DELETE" do
      %w(PUT PATCH DELETE).each do |method|
        header = HTTP::Headers.new
        header["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("HEAD", "/?test=test", header, "_method=#{method}")

        context = create_context(request)

        context.request.method.should eq "HEAD"
      end
    end
  end

  it "parses query params" do
    request = HTTP::Request.new("GET", "/?test=test")

    context = create_context(request)

    context.params["test"].should eq "test"
  end

  it "parses multiple query params" do
    request = HTTP::Request.new("GET", "/?test=test&test2=test2")

    context = create_context(request)

    context.params["test2"].should eq "test2"
  end

  it "responds to cookies" do
    request = HTTP::Request.new("GET", "/?test=test&test2=test2")

    context = create_context(request)

    context.responds_to?(:cookies).should eq true
  end

  it "parses body params" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    body = "test=test"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["test"].should eq "test"
  end

  it "parses body params with charset" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
    body = "\x68\x65\x6C\x6C\x6F\x3D\x77\x6F\x72\x6C\x64"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["hello"]?.should eq "world"
  end

  it "parses multiple body params" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    body = "test=test&test2=test2"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["test2"].should eq "test2"
  end

  it "parses json hash" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/json"
    body = %({ "test": "test", "address": { "city": "New York" }})
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["test"].should eq "test"
    context.params["address"].as(Hash)["city"].should eq "New York"
  end

  it "parses json array" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/json"
    body = %(["test", "test2"])
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["_json"].should eq %w(test test2)
  end

  it "parses files from multipart forms" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX"
    body = "--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\nPcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\ntitle field\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"picture\"; filename=\"index.html\"\r\nContent-Type: text/html\r\n\r\n<head></head><body>Hello World!</body>\r\n\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nseriously\r\n--fhhRFLCazlkA0dX--"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.files["picture"].filename.should eq "index.html"
    context.params["title"].should eq "title field"
    context.params["_csrf"].should eq "PcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI"
  end

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
        headers[HTTP::Server::Context::FORMAT_HEADER] = content_type
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.format.should eq format.to_s
      end
    end
  end

  describe "#client_ip" do
    HTTP::Server::Context::IP_ADDRESS_HEADERS.each do |header|
      it "gets client ip from #{header} headers" do
        ip_address = "102.168.35.88"
        headers = HTTP::Headers.new
        headers[header] = ip_address
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.client_ip.should eq ip_address
      end

      it "gets client ip from #{header} headers" do
        ip_address = "102.168.35.88"
        headers = HTTP::Headers.new
        headers[header.tr("_", "-")] = ip_address
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.client_ip.should eq ip_address
      end

      it "gets client ip from #{header} headers" do
        ip_address = "102.168.35.88"
        headers = HTTP::Headers.new
        headers["HTTP_#{header}"] = ip_address
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.client_ip.should eq ip_address
      end

      it "gets client ip from #{header} headers" do
        ip_address = "102.168.35.88"
        headers = HTTP::Headers.new
        headers["Http-#{header}"] = ip_address
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.client_ip.should eq ip_address
      end

      it "gets client ip from #{header} headers" do
        ip_address = "102.168.35.88"
        headers = HTTP::Headers.new
        headers["HTTP-#{header}"] = ip_address
        request = HTTP::Request.new("GET", "/", headers)
        context = create_context(request)
        context.client_ip.should eq ip_address
      end
    end
  end
end
