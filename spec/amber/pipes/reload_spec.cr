require "../../spec_helper"

class FakeEnvironment < Amber::Environment::Env
  def development?
    true
  end
end

module Amber
  module Pipe
    describe Reload do
      headers = HTTP::Headers.new
      headers["Accept"] = "text/html"
      request = HTTP::Request.new("GET", "/reload", headers)

      Amber::Server.router.draw :web do
        get "/reload", HelloController, :index
      end

      context "when environment is in development mode" do
        pipeline = Pipeline.new
        pipeline.build :web do
          plug Amber::Pipe::Reload.new(FakeEnvironment.new)
        end
        pipeline.prepare_pipelines

        it "contains injected header in response" do
          response = create_request_and_return_io(pipeline, request)

          response.headers["Client-Reload"]?.should_not be_nil
        end
      end

      context "when environment is NOT in development mode" do
        pipeline = Pipeline.new
        pipeline.build :web do
          plug Amber::Pipe::Reload.new
        end
        pipeline.prepare_pipelines

        it "does not have injected header in response" do
          response = create_request_and_return_io(pipeline, request)

          response.headers["Client-Reload"]?.should be_nil
        end
      end
    end
  end
end
