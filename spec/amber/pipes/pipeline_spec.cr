require "../../spec_helper"

module Amber
  module Pipe
    # Accepts the first request it is asked about and rejects every later
    # call, so a second check of the same request would answer 404.
    class AcceptsOnceConstraint
      include Amber::Router::Constraint

      getter calls = 0

      def matches?(request : HTTP::Request) : Bool
        @calls += 1
        @calls == 1
      end
    end

    # Rejects every request.
    class RejectsAllConstraint
      include Amber::Router::Constraint

      def matches?(request : HTTP::Request) : Bool
        false
      end
    end

    describe Pipeline do
      it "connects pipes to the pipeline for given valve" do
        pipeline = Pipeline.new

        pipeline.build :api do
          plug Pipe::Logger.new
          plug Pipe::Error.new
        end
        # Should eq 3 because of default pipe
        pipeline.pipeline[:api].size.should eq 2
      end

      describe "with given server config" do
        pipeline = Pipeline.new
        before_each do
          pipeline = Pipeline.new

          Amber::Server.router.draw :web do
            get "/valid/route", HelloController, :world
            get "/index/:name", HelloController, :world
            resources "/hello", HelloController
          end

          pipeline.build :web { }
          pipeline.prepare_pipelines
        end

        it "asks a declared extension route's request constraint once" do
          accepts_once = AcceptsOnceConstraint.new
          Amber::Server.router.draw :web do
            get "/report", HelloController, :world
            constraint accepts_once do
              get "/report.md", HelloController, :world
            end
          end

          request = HTTP::Request.new("GET", "/report.md")
          create_request_and_return_io(pipeline, request).status_code.should eq 200
          accepts_once.calls.should eq 1
        end

        it "checks the finally matched route's constraint after a preflight lookup accepted another route" do
          accepts_once = AcceptsOnceConstraint.new
          rejects_all = RejectsAllConstraint.new
          Amber::Server.router.draw :web do
            constraint rejects_all do
              get "/summary", HelloController, :world
            end
            constraint accepts_once do
              get "/summary.md", HelloController, :world
            end
          end

          request = HTTP::Request.new("GET", "/summary.md")
          Amber::Server.router.route_defined?(request).should be_true
          create_request_and_return_io(pipeline, request).status_code.should eq 404
        end

        it "raises exception when route not found" do
          request = HTTP::Request.new("GET", "/bad/route")
          create_request_and_return_io(pipeline, request).status_code.should eq 404
        end

        it "routes" do
          request = HTTP::Request.new("GET", "/index/elias")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Hello World!"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to GET request" do
          request = HTTP::Request.new("GET", "/hello")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Index"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to PUT request" do
          request = HTTP::Request.new("PUT", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Update"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to PATCH request" do
          request = HTTP::Request.new("PATCH", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Update"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to POST request" do
          request = HTTP::Request.new("POST", "/hello")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Create"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to DELETE request" do
          request = HTTP::Request.new("DELETE", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Destroy"
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end

        it "responds to HEAD request" do
          request = HTTP::Request.new("HEAD", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.headers["Content-Length"].should eq "0"
          response.body.empty?.should be_true
          response.headers[HTTP::Server::Context::CONTENT_TYPE].should eq "text/html"
        end
      end
    end
  end
end
