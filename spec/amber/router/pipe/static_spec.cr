require "../../../spec_helper"
require "../../../support/helpers/router_helper"

include RouterHelper

module Amber
  module Pipe
    TEST_PUBLIC_PATH = "spec/support/sample/public"
    describe Static do
      it "renders html" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH, false

        response = create_request_and_return_io(static, request)

        response.body.should eq "<head></head><body>Hello World!</body>\n"
      end

      it "returns Not Found when file doesn't exist" do
        request = HTTP::Request.new("GET", "/not_found.html")
        static = Static.new PUBLIC_PATH, false

        response = create_request_and_return_io(static, request)

        response.body.should eq "Not Found\n"
      end

      it "delivers index.html if path ends with /" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH, false

        response = create_request_and_return_io(static, request)

        response.body.should eq "<head></head><body>Hello World!</body>\n"
      end

      it "serves the correct content type for serve file" do
        %w(png svg css js).each do |ext|
          file = File.expand_path(TEST_PUBLIC_PATH) + "/fake.#{ext}"
          File.write(file, "")
          request = HTTP::Request.new("GET", "/fake.#{ext}")
          static = Static.new PUBLIC_PATH, false
          response = create_request_and_return_io(static, request)
          response.headers["content-type"].should eq(Amber::Support::MimeTypes.mime_type(ext))
          File.delete(file)
        end
      end
    end
  end
end
