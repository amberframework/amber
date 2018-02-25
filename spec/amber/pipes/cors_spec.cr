require "../../../spec_helper"

module Amber::Pipe
  describe CORS do
    it "supports simple CORS requests" do
      context = cors_context("GET", "Origin": "http://localhost:3000")
      CORS.new.call(context)
      assert_cors_success(context)
    end

    it "does not return CORS headers if Origin header not present" do
      context = cors_context("GET")
      CORS.new.call(context)
      assert_cors_not_success context
    end

    it "supports OPTIONS request" do
      context = cors_context("OPTIONS", "Origin": "example.com")
      CORS.new.call(context)
      assert_cors_success context
    end

    it "matches regex :origin settings" do
      context = cors_context("GET", "Origin": "http://192.168.0.1:3000")
      origins = CORS::OriginType.new
      origins << %r(192\.168\.0\.1)
      CORS.new(origins: origins).call(context)
      assert_cors_success(context)
    end

    it "does not return CORS headers if origins is empty" do
      context = cors_context("GET", "Origin": "http://localhost:3000")
      CORS.new(origins: CORS::OriginType.new).call(context)
      assert_cors_not_success context
    end

    it "supports alternative X-Origin header" do
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      CORS.new.call(context)
      assert_cors_success(context)
    end

    it "supports expose header configuration" do
      expose_header = %w(X-Expose)
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      CORS.new(expose_headers: expose_header).call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_EXPOSE].should eq expose_header.join(",")
    end

    it "supports expose multiple header configuration" do
      expose_header = %w(X-Example X-Another)
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      CORS.new(expose_headers: expose_header).call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_EXPOSE].should eq expose_header.join(",")
    end

    it "adds vary header when origin is other than (*)" do
      origins = CORS::OriginType.new
      origins << "example.com"
      context = cors_context("GET", "Origin": "example.com")
      CORS.new(origins: origins).call(context)
      context.response.headers[Amber::Pipe::Headers::VARY].should eq "Origin"
    end

    it "does not add vary header when origin is (*)" do
      origins = CORS::OriginType.new
      origins << "*"
      context = cors_context("GET", "Origin": "*")
      CORS.new(origins: origins).call(context)
      context.response.headers[Amber::Pipe::Headers::VARY]?.should be_nil
    end

    it "adds Vary header based on :vary option" do
      origins = CORS::OriginType.new
      origins << "example.com"
      context = cors_context("GET", "Origin": "example.com")
      CORS.new(origins: origins, vary: "Other").call(context)
      context.response.headers[Amber::Pipe::Headers::VARY].should eq "Origin,Other"
    end

    it "sets allow credential headers if credential settings is true" do
      origins = CORS::OriginType.new
      origins << "example.com"
      context = cors_context("GET", "Origin": "example.com")
      CORS.new(credentials: true, origins: origins, vary: "Other").call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_CREDENTIALS].should eq "true"
    end

    context "when preflight request" do
      it "process valid preflight request" do
        origins = CORS::OriginType.new
        origins << "example.com"
        context = cors_context(
          "OPTIONS",
          "Origin": "example.com",
          "Access-Control-Request-Method": "PUT",
          "Access-Control-Request-Headers": "Accept"
        )
        CORS.new(origins: origins).call(context)

        context.response.status_code = 200
        context.response.headers["Content-Length"].should eq "0"
      end
    end
  end
end

def cors_context(method = "GET", **args)
  headers = HTTP::Headers.new
  args.each do |k, v|
    headers[k.to_s] = v
  end
  request = HTTP::Request.new(method, "/", headers)
  create_context(request)
end

def assert_cors_success(context)
  origin_header = context.response.headers["Access-Control-Allow-Origin"]?
  origin_header.should_not be_nil
end

def assert_cors_not_success(context)
  origin_header = context.response.headers["Access-Control-Allow-Origin"]?
  context.response.status_code.should eq 403
  origin_header.should be_nil
end
