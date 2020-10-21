require "../../spec_helper"
require "../../support/helpers/router_helper"

include RouterHelper

module Amber
  module Pipe
    TEST_PUBLIC_PATH = "spec/support/sample/public"
    describe Static do
      it "renders html" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH

        response = create_request_and_return_io(static, request)

        response.body.should eq "<head></head><body>Hello World!</body>\n"
      end

      it "returns Not Found when file doesn't exist" do
        request = HTTP::Request.new("GET", "/not_found.html")
        static = Static.new PUBLIC_PATH

        response = create_request_and_return_io(static, request)

        response.body.should eq "404 Not Found\n"
      end

      it "delivers index.html if path ends with /" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH

        response = create_request_and_return_io(static, request)

        response.body.should eq "<head></head><body>Hello World!</body>\n"
      end

      it "serves the correct content type for serve file" do
        %w(png svg css js).each do |ext|
          file = File.expand_path(TEST_PUBLIC_PATH) + "/fake.#{ext}"
          File.write(file, "")
          request = HTTP::Request.new("GET", "/fake.#{ext}")
          static = Static.new PUBLIC_PATH
          response = create_request_and_return_io(static, request)
          response.headers["content-type"].should eq(Amber::Support::MimeTypes.mime_type(ext))
          File.delete(file)
        end
      end

      it "returns Not Found when directory_listing is disabled" do
        request = HTTP::Request.new("GET", "/dist")
        static_true = Static.new PUBLIC_PATH, directory_listing: true
        static_false = Static.new PUBLIC_PATH # Listing is off by default in Amber

        response_true = create_request_and_return_io(static_true, request)
        response_false = create_request_and_return_io(static_false, request)

        response_true.body.should match(/index/)
        response_false.status_code.should eq 404
      end

      it "sets default response headers" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH

        response = create_request_and_return_io(static, request)

        response.headers["Accept-Ranges"].should eq "bytes"
        response.headers["X-Content-Type-Options"].should eq "nosniff"
        response.headers["Cache-Control"].should eq "no-store"
      end

      it "lists the directory when directory_listing is enabled" do
        request = HTTP::Request.new("GET", "/test")
        static_true = Static.new PUBLIC_PATH, directory_listing: true

        response_true = create_request_and_return_io(static_true, request)

        response_true.headers["Location"].should eq "/test/"

        response_true.status_code.should eq 302
      end
    end
  end
end
