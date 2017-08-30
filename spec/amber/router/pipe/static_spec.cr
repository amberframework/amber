require "../../../spec_helper"

module Amber
  module Pipe
    TEST_PUBLIC_PATH = "src/support/sample/public"
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
    end
  end
end
