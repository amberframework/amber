require "../../spec_helper"
require "../../support/helpers/router_helper"

include RouterHelper

module Amber
  module Pipe
    TEST_PUBLIC_PATH = "spec/support/sample/public"

    # An application handler ahead of the static pipe that marks every
    # response private.
    class PrivateResponses
      include HTTP::Handler

      def call(context : HTTP::Server::Context) : Nil
        context.response.headers["Cache-Control"] = "private, no-store"
        call_next(context)
      end
    end

    # Stands in for the controller that answers a path with no static file.
    class DynamicAnswer
      include HTTP::Handler

      def call(context : HTTP::Server::Context) : Nil
        context.response.print "dynamic"
      end
    end

    # A static pipe whose fingerprints are 8 hex characters, so it supplies
    # its own cache policy through the `cache_control` hook.
    class StaticWithShortFingerprints < Static
      protected def cache_control(request_path : String) : String
        if Static.fingerprinted?(request_path, hex_lengths: 8..8)
          IMMUTABLE_CACHE_CONTROL
        else
          "public, max-age=60"
        end
      end
    end

    describe ".fingerprinted?" do
      it "accepts 16 to 64 hex digits of either case between a dash and a dot" do
        Static.fingerprinted?("/assets/app-#{"a" * 16}.css").should be_true
        Static.fingerprinted?("/assets/app-#{"A" * 64}.css").should be_true
        Static.fingerprinted?("/assets/app-#{"0123456789abcdef"}.min.css").should be_true
      end

      it "rejects a hex run shorter than 16 or longer than 64" do
        Static.fingerprinted?("/assets/app-#{"a" * 15}.css").should be_false
        Static.fingerprinted?("/assets/app-#{"a" * 65}.css").should be_false
      end

      it "needs at least one character after the dot, in the last segment" do
        Static.fingerprinted?("/assets/app-#{"a" * 16}.").should be_false
        Static.fingerprinted?("/assets-#{"a" * 16}.d/app.css").should be_false
      end

      it "finds a later dash when an earlier one starts no fingerprint" do
        Static.fingerprinted?("/assets/my-app-#{"a" * 16}.css").should be_true
      end

      it "rejects a path that is not valid UTF-8" do
        path = String.new("/app-0123456789abcdef.".to_slice + Bytes[0xFF])
        Static.fingerprinted?(path).should be_false
      end

      it "takes the hex lengths a subclass asks for" do
        Static.fingerprinted?("/a-0123abcd.js", hex_lengths: 8..8).should be_true
        Static.fingerprinted?("/a-0123abcd9.js", hex_lengths: 8..8).should be_false
      end
    end

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

      # Note: This test will fail on older systems that still expect "application/javascript" to be valid content-type, but this is deprecated
      it "serves the correct content type for serve file" do
        %w(png svg css js).each do |ext|
          file = File.expand_path(TEST_PUBLIC_PATH) + "/fake.#{ext}"
          File.write(file, "")
          request = HTTP::Request.new("GET", "/fake.#{ext}")
          static = Static.new PUBLIC_PATH
          response = create_request_and_return_io(static, request)
          response.headers["content-type"].should contain(Amber::Support::MimeTypes.mime_type(ext))
          File.delete(file)
        end
      end

      it "returns Not Found when directory_listing is disabled" do
        request = HTTP::Request.new("GET", "/dist/")
        static_true = Static.new PUBLIC_PATH, directory_listing: true
        static_false = Static.new PUBLIC_PATH # Listing is off by default in Amber

        response_true = create_request_and_return_io(static_true, request)
        response_false = create_request_and_return_io(static_false, request)

        response_true.body.should match(/index.html/)
        response_false.status_code.should eq 404
      end

      it "sets default response headers" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH

        response = create_request_and_return_io(static, request)

        response.headers["Accept-Ranges"].should eq "bytes"
        response.headers["Cache-Control"].should eq "no-store"
        response.headers["X-Content-Type-Options"].should eq "nosniff"
        response.headers["Vary"].should eq "Accept-Encoding"
      end

      it "applies explicit configured headers to static files" do
        request = HTTP::Request.new("GET", "/index.html")
        static = Static.new PUBLIC_PATH, headers: {
          "Cache-Control" => "private, max-age=60",
          "X-Asset-Test"  => "configured",
        }

        response = create_request_and_return_io(static, request)

        response.headers["Cache-Control"].should eq "private, max-age=60"
        response.headers["X-Asset-Test"].should eq "configured"
      end

      it "uses immutable caching for fingerprinted assets" do
        filename = "app-0123456789abcdef.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "body {}")

        begin
          request = HTTP::Request.new("GET", "/#{filename}")
          static = Static.new PUBLIC_PATH, headers: {"Cache-Control" => "private"}
          response = create_request_and_return_io(static, request)

          response.headers["Cache-Control"].should eq Static::IMMUTABLE_CACHE_CONTROL
        ensure
          File.delete?(file)
        end
      end

      it "keeps a Cache-Control that an earlier handler set" do
        filename = "app-0123456789abcdef.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "body {}")

        begin
          {"Cache-Control", "cache-control", "Cache_Control"}.each do |configured_name|
            earlier_handler = PrivateResponses.new
            earlier_handler.next = Static.new PUBLIC_PATH, headers: {configured_name => "public, max-age=60"}

            response = create_request_and_return_io(earlier_handler, HTTP::Request.new("GET", "/#{filename}"))

            response.headers.get("Cache-Control").should eq ["private, no-store"]
            response.headers["X-Content-Type-Options"].should eq "nosniff"
          end
        ensure
          File.delete?(file)
        end
      end

      it "applies a configured Cache-Control spelled in any case or with underscores" do
        static = Static.new PUBLIC_PATH, headers: {"cache_control" => "private, max-age=60"}

        response = create_request_and_return_io(static, HTTP::Request.new("GET", "/index.html"))

        response.headers.get("Cache-Control").should eq ["private, max-age=60"]
      end

      it "attaches no asset headers to a method other than GET or HEAD" do
        filename = "app-0123456789abcdef.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "body {}")

        begin
          refused = create_request_and_return_io(Static.new(PUBLIC_PATH), HTTP::Request.new("POST", "/#{filename}"))
          refused.status_code.should eq 405
          refused.headers["Cache-Control"]?.should be_nil

          static = Static.new PUBLIC_PATH, fallthrough: true
          static.next = DynamicAnswer.new
          passed_on = create_request_and_return_io(static, HTTP::Request.new("POST", "/#{filename}"))
          passed_on.body.should eq "dynamic"
          passed_on.headers["Cache-Control"]?.should be_nil
          passed_on.headers["X-Content-Type-Options"]?.should be_nil
        ensure
          File.delete?(file)
        end
      end

      it "leaves Cache-Control to the next handler when no file matches" do
        static = StaticWithShortFingerprints.new PUBLIC_PATH, fallthrough: true
        static.next = DynamicAnswer.new

        response = create_request_and_return_io(static, HTTP::Request.new("GET", "/account-0123abcd.css"))

        response.body.should eq "dynamic"
        response.headers["Cache-Control"]?.should be_nil
      end

      it "lets a subclass supply its cache policy through #cache_control" do
        filename = "app-0123abcd.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "body {}")

        begin
          static = StaticWithShortFingerprints.new PUBLIC_PATH, headers: {"Cache-Control" => "no-store"}

          fingerprinted = create_request_and_return_io(static, HTTP::Request.new("GET", "/#{filename}"))
          fingerprinted.headers["Cache-Control"].should eq Static::IMMUTABLE_CACHE_CONTROL

          plain = create_request_and_return_io(static, HTTP::Request.new("GET", "/index.html"))
          plain.headers["Cache-Control"].should eq "public, max-age=60"
        ensure
          File.delete?(file)
        end
      end

      it "serves portable image, font, manifest, and source-map MIME types" do
        expected_types = {
          "avif"        => "image/avif",
          "cjs"         => "text/javascript; charset=utf-8",
          "json"        => "application/json; charset=utf-8",
          "woff"        => "font/woff",
          "woff2"       => "font/woff2",
          "wasm"        => "application/wasm",
          "webmanifest" => "application/manifest+json; charset=utf-8",
          "map"         => "application/json; charset=utf-8",
        }

        expected_types.each do |extension, expected_type|
          unless {"cjs", "json", "map", "wasm", "webmanifest"}.includes?(extension)
            Amber::Support::MimeTypes.mime_type(extension).should eq expected_type
          end
          file = File.join(File.expand_path(TEST_PUBLIC_PATH), "portable.#{extension}")
          File.write(file, "fixture")

          begin
            request = HTTP::Request.new("GET", "/portable.#{extension}")
            response = create_request_and_return_io(Static.new(PUBLIC_PATH), request)
            response.headers["Content-Type"].should eq expected_type
          ensure
            File.delete?(file)
          end
        end
      end

      it "does not attach asset caching headers to a missing file" do
        request = HTTP::Request.new("GET", "/missing-0123456789abcdef.css")
        response = create_request_and_return_io(Static.new(PUBLIC_PATH), request)

        response.status_code.should eq 404
        response.headers["Cache-Control"]?.should be_nil
      end

      it "keeps conditional requests working with immutable headers" do
        filename = "conditional-0123456789abcdef.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "body { color: black; }")

        begin
          initial = create_request_and_return_io(
            Static.new(PUBLIC_PATH),
            HTTP::Request.new("GET", "/#{filename}")
          )
          headers = HTTP::Headers{"If-None-Match" => initial.headers["Etag"]}
          cached = create_request_and_return_io(
            Static.new(PUBLIC_PATH),
            HTTP::Request.new("GET", "/#{filename}", headers)
          )

          cached.status_code.should eq 304
          cached.headers["Cache-Control"].should eq Static::IMMUTABLE_CACHE_CONTROL
        ensure
          File.delete?(file)
        end
      end

      it "keeps byte ranges working for fingerprinted binary assets" do
        filename = "sample-0123456789abcdef.wasm"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        File.write(file, "0123456789")

        begin
          request = HTTP::Request.new(
            "GET",
            "/#{filename}",
            HTTP::Headers{"Range" => "bytes=2-5"}
          )
          response = create_request_and_return_io(Static.new(PUBLIC_PATH), request)

          response.status_code.should eq 206
          response.body.should eq "2345"
          response.headers["Content-Range"].should eq "bytes 2-5/10"
          response.headers["Cache-Control"].should eq Static::IMMUTABLE_CACHE_CONTROL
        ensure
          File.delete?(file)
        end
      end

      it "serves precompressed files and varies on content encoding" do
        filename = "compressed-0123456789abcdef.css"
        file = File.join(File.expand_path(TEST_PUBLIC_PATH), filename)
        gzip_file = "#{file}.gz"
        File.write(file, "body { color: black; }")
        File.write(gzip_file, "precompressed-fixture")

        begin
          request = HTTP::Request.new(
            "GET",
            "/#{filename}",
            HTTP::Headers{"Accept-Encoding" => "gzip"}
          )
          response = create_request_and_return_io(Static.new(PUBLIC_PATH), request)

          response.headers["Content-Encoding"].should eq "gzip"
          response.headers["Vary"].should contain "Accept-Encoding"
          response.headers["Content-Type"].should contain "text/css"
        ensure
          File.delete?(gzip_file)
          File.delete?(file)
        end
      end

      it "does not treat a traversal request as an asset" do
        request = HTTP::Request.new("GET", "/%2e%2e/shard.yml")
        response = create_request_and_return_io(Static.new(PUBLIC_PATH), request)

        response.status_code.should eq 302
        response.headers["Cache-Control"]?.should be_nil
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
