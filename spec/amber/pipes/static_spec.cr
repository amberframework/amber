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
