require "../../spec_helper"

module Amber::Pipe
  describe CORS do
    it "supports simple CORS requests" do
      context = cors_context("GET", "Origin": "http://localhost:3000")
      cors_add_next(CORS.new).call(context)
      assert_cors_success(context)
    end

    it "process requests as normal for non CORS requests" do
      context = cors_context("GET")
      cors_add_next(CORS.new).call(context)
      assert_non_cors_request context
    end

    it "supports OPTIONS request" do
      context = cors_context("OPTIONS", "Origin": "example.com")
      cors_add_next(CORS.new).call(context)
      assert_cors_success context
    end

    it "matches regex :origin settings" do
      context = cors_context("GET", "Origin": "http://192.168.0.1:3000")
      origins = CORS::OriginType.new
      origins << %r(192\.168\.0\.1)
      cors_add_next(CORS.new(origins: origins)).call(context)
      assert_cors_success(context)
    end

    it "does not return CORS headers if origins is empty" do
      context = cors_context("GET", "Origin": "http://localhost:3000")
      cors_add_next(CORS.new(origins: CORS::OriginType.new)).call(context)
      assert_cors_failure context
    end

    it "supports alternative X-Origin header" do
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      cors_add_next(CORS.new).call(context)
      assert_cors_success(context)
    end

    it "supports expose header configuration" do
      expose_header = %w(X-Expose)
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      cors_add_next(CORS.new(expose_headers: expose_header)).call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_EXPOSE].should eq expose_header.join(",")
    end

    it "supports expose multiple header configuration" do
      expose_header = %w(X-Example X-Another)
      context = cors_context("GET", "X-Origin": "http://localhost:3000")
      cors_add_next(CORS.new(expose_headers: expose_header)).call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_EXPOSE].should eq expose_header.join(",")
    end

    it "adds vary header when origin is other than (*)" do
      context = cors_context("GET", "Origin": "example.com")
      cors_add_next(CORS.new(origins: origins)).call(context)
      context.response.headers[Amber::Pipe::Headers::VARY].should eq "Origin"
    end

    it "does not add vary header when origin is (*)" do
      origins = CORS::OriginType.new
      origins << "*"
      context = cors_context("GET", "Origin": "*")
      cors_add_next(CORS.new(origins: origins)).call(context)
      context.response.headers[Amber::Pipe::Headers::VARY]?.should be_nil
    end

    it "adds Vary header based on :vary option" do
      context = cors_context("GET", "Origin": "example.com")
      cors_add_next(CORS.new(origins: origins, vary: "Other")).call(context)
      context.response.headers[Amber::Pipe::Headers::VARY].should eq "Origin,Other"
    end

    it "sets allow credential headers if credential settings is true" do
      context = cors_context("GET", "Origin": "example.com")
      cors_add_next(CORS.new(credentials: true, origins: origins, vary: "Other")).call(context)
      context.response.headers[Amber::Pipe::Headers::ALLOW_CREDENTIALS].should eq "true"
    end

    context "when preflight request" do
      context "valid preflight" do
        it "returns status code 200" do
          context = cors_context(
            "OPTIONS",
            "Origin": "example.com",
            "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "CoNtEnT-TyPe"
          )
          cors_add_next(CORS.new(origins: origins)).call(context)

          context.response.status_code = 200
          context.response.headers["Content-Length"].should eq "0"
        end

        it "should set the correct headers" do
          context = cors_context(
            "OPTIONS",
            "Origin": "example.com",
            "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "CoNtEnT-TyPe"
          )
          cors_add_next(CORS.new(origins: origins)).call(context)

          context.response.status_code = 200
          context.response.headers["Access-Control-Allow-Methods"].should eq "PUT"
          context.response.headers["Access-Control-Allow-Headers"].should eq "CoNtEnT-TyPe"
          context.response.headers["Access-Control-Allow-Origin"].should eq "example.com"
        end

        context "after a previous valid preflight from another Origin" do
          it "should set the correct headers" do
            cors = cors_add_next(CORS.new(origins: origins))

            previous_context = cors_context(
              "OPTIONS",
              "Origin": "sample.com",
              "Access-Control-Request-Method": "POST",
              "Access-Control-Request-Headers": "CoNtEnT-TyPe"
            )
            cors.call(previous_context)

            context = cors_context(
              "OPTIONS",
              "Origin": "example.com",
              "Access-Control-Request-Method": "PUT",
              "Access-Control-Request-Headers": "CoNtEnT-TyPe"
            )
            cors.call(context)

            context.response.status_code = 200
            context.response.headers["Access-Control-Allow-Methods"].should eq "PUT"
            context.response.headers["Access-Control-Allow-Headers"].should eq "CoNtEnT-TyPe"
            context.response.headers["Access-Control-Allow-Origin"].should eq "example.com"
          end
        end
      end

      context "invalid preflight" do
        it "return status 403 Forbidden" do
          context = cors_context(
            "OPTIONS",
            "Origin": "example.com",
            "Access-Control-Request-Method": "unsupported method",
            "Access-Control-Request-Headers": "CoNtEnT-TyPe"
          )
          cors_add_next(CORS.new(origins: origins)).call(context)

          context.response.status_code.should eq 403
        end

        it "return status 403 Forbidden when missing preflight header" do
          context = cors_context(
            "OPTIONS",
            "Origin": "example.com",
            "Access-Control-Request-Method": "PUT",
          )
          cors_add_next(CORS.new(origins: origins)).call(context)

          context.response.status_code.should eq 403
        end
      end
    end
  end
end
