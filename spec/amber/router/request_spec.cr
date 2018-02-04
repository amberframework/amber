require "../../../spec_helper"

describe HTTP::Request do
  header = HTTP::Headers.new

  describe "#method" do
    it "overrides form POST method to PUT, PATCH, DELETE" do
      %w(PUT PATCH DELETE).each do |method|
        header[HTTP::Request::OVERRIDE_HEADER] = method
        request = HTTP::Request.new("POST", "/?test=test", header)
        request.method.should eq method
      end
    end

    it "overrides form GET method to PUT, PATCH, DELETE" do
      %w(PUT PATCH DELETE).each do |method|
        header[HTTP::Request::OVERRIDE_HEADER] = method
        request = HTTP::Request.new("GET", "/?test=test", header)
        request.method.should eq method
      end
    end

    it "takes form post over header override" do
      %w(PUT PATCH DELETE).each do |method|
        header[HTTP::Request::OVERRIDE_HEADER] = method
        header["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("GET", "/?test=test", header, "_method=PATCH")
        request.method.should eq "PATCH"
      end
    end

    it "overrides form request method only by upper case value" do
      header["content-type"] = "application/x-www-form-urlencoded"
      request = HTTP::Request.new("GET", "/?test=test", header, "_method=put")
      request.method.should eq "PUT"
    end
  end

  it "overrides form POST method to PUT, PATCH, DELETE" do
    %w(PUT PATCH DELETE).each do |method|
      header = HTTP::Headers.new
      header["content-type"] = "application/x-www-form-urlencoded"
      request = HTTP::Request.new("POST", "/?test=test", header, "_method=#{method}")
      request.method.should eq method
    end
  end

  it "overrides form GET method to PUT, PATCH, DELETE" do
    %w(PUT PATCH DELETE).each do |method|
      header = HTTP::Headers.new
      header["content-type"] = "application/x-www-form-urlencoded"
      request = HTTP::Request.new("GET", "/?test=test", header, "_method=#{method}")
      request.method.should eq method
    end
  end

  it "does not override other than PUT, PATCH, DELETE" do
    %w(PUT PATCH DELETE).each do |method|
      header["content-type"] = "application/x-www-form-urlencoded"
      request = HTTP::Request.new("HEAD", "/?test=test", header, "_method=#{method}")
      request.method.should eq "HEAD"
    end
  end
end