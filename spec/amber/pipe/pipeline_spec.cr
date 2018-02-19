require "../../../spec_helper"

module Amber
  module Pipe
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

        Amber::Server.router.draw :web do
          get "/valid/route", HelloController, :world
          get "/index/:name", HelloController, :world
          resources "/hello", HelloController
        end

        pipeline.build :web { }
        pipeline.prepare_pipelines

        it "raises exception when route not found" do
          request = HTTP::Request.new("GET", "/bad/route")
          create_request_and_return_io(pipeline, request).status_code.should eq 404
        end

        it "routes" do
          request = HTTP::Request.new("GET", "/index/elias")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Hello World!"
        end

        it "responds to GET request" do
          request = HTTP::Request.new("GET", "/hello")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Index"
        end

        it "responds to PUT request" do
          request = HTTP::Request.new("PUT", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Update"
        end

        it "responds to PATCH request" do
          request = HTTP::Request.new("PATCH", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Update"
        end

        it "responds to POST request" do
          request = HTTP::Request.new("POST", "/hello")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Create"
        end

        it "responds to DELETE request" do
          request = HTTP::Request.new("DELETE", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.body.should eq "Destroy"
        end

        it "responds to HEAD request" do
          request = HTTP::Request.new("HEAD", "/hello/1")
          response = create_request_and_return_io(pipeline, request)
          response.headers["Content-Length"].should eq "0"
          response.body.empty?.should be_true
        end
      end
    end
  end
end
