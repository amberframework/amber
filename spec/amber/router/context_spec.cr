require "../../../spec_helper"

describe HTTP::Server::Context do
  describe "#override_request_method!" do
    describe "when X-HTTP-Method-Overrid is present" do
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
    body = "{\"test\":\"test\"}"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["test"].should eq "test"
  end

  it "parses json array" do
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/json"
    body = "[\"test\",\"test2\"]"
    request = HTTP::Request.new("POST", "/", headers, body)

    context = create_context(request)

    context.params["_json"].should eq "[\"test\", \"test2\"]"
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
end
