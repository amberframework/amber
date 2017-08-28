require "../../../../spec_helper"

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

      describe "#call" do
        it "raises exception when route not found" do
          pipeline = Pipeline.new
          request = HTTP::Request.new("GET", "/bad/route")
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { get "/valid/route", HelloController, :world }
          create_request_and_return_io(pipeline, request).status_code.should eq 404
        end

        it "routes" do
          pipeline = Pipeline.new
          request = HTTP::Request.new("GET", "/index/elias")
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { get "/index/:name", HelloController, :world }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Hello World!"
        end
      end

      describe "http requests" do
        it "perform GET request" do
          request = HTTP::Request.new("GET", "/hello")
          pipeline = Pipeline.new
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { get "/hello", HelloController, :index }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Index"
        end

        it "perform PUT request" do
          request = HTTP::Request.new("PUT", "/hello/1")
          pipeline = Pipeline.new
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { put "/hello/:id", HelloController, :update }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Update"
        end

        it "perform PATCH request" do
          request = HTTP::Request.new("PATCH", "/hello/1")
          pipeline = Pipeline.new
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { patch "/hello/:id", HelloController, :update }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Update"
        end

        it "perform POST request" do
          request = HTTP::Request.new("POST", "/hello")
          pipeline = Pipeline.new
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { post "/hello", HelloController, :create }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Create"
        end

        it "perform DELETE request" do
          request = HTTP::Request.new("DELETE", "/hello/1")
          pipeline = Pipeline.new
          pipeline.build :web { plug Amber::Pipe::Logger.new }
          Router::Router.instance.draw :web { delete "/hello/:id", HelloController, :destroy }

          pipeline.prepare_pipelines
          response = create_request_and_return_io(pipeline, request)

          response.body.should eq "Destroy"
        end
      end
    end
  end
end
