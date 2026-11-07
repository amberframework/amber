require "../../spec_helper"

module Amber::Support
  describe MimeTypes do
    describe ".path_extension_format" do
      it "returns the MIME_TYPES key after the last dot" do
        MimeTypes.path_extension_format("/users.json").should eq "json"
        MimeTypes.path_extension_format("/v1.2/report.pdf").should eq "pdf"
        MimeTypes.path_extension_format("/a.b.txt").should eq "txt"
        MimeTypes.path_extension_format("/launch.fe_launch").should eq "fe_launch"
      end

      it "returns nil when the text after the last dot is no key" do
        MimeTypes.path_extension_format("/users").should be_nil
        MimeTypes.path_extension_format("/users.json.bak").should be_nil
        MimeTypes.path_extension_format("/v1.2/users").should be_nil
        MimeTypes.path_extension_format("/users.JSON").should be_nil
        MimeTypes.path_extension_format("/users.").should be_nil
      end
    end

    describe ".get_request_format" do
      it "prefers the path extension" do
        request = HTTP::Request.new("GET", "/users.json", HTTP::Headers{"Accept" => "text/html"})
        MimeTypes.get_request_format(request).should eq "json"
      end

      it "takes the first Accept media range, without its parameters" do
        request = HTTP::Request.new("GET", "/users", HTTP::Headers{"Accept" => "application/json;q=0.9, text/html"})
        MimeTypes.get_request_format(request).should eq "json"
      end

      it "answers html when the Accept header is missing or empty" do
        MimeTypes.get_request_format(HTTP::Request.new("GET", "/users")).should eq "html"
        request = HTTP::Request.new("GET", "/users", HTTP::Headers{"Accept" => ""})
        MimeTypes.get_request_format(request).should eq "html"
      end
    end
  end
end
