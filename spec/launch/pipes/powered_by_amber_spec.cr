require "../../spec_helper"

module Launch
  module Pipe
    describe PoweredByLaunch do
      context "Adds X-Powered-By: Launch to response" do
        it "should contain X-Powered-By in response" do
          pipeline = Pipeline.new

          pipeline.build :web do
            plug PoweredByLaunch.new
          end

          Launch::Server.router.draw :web do
            options "/poweredbylaunch", HelloController, :world
          end

          pipeline.prepare_pipelines

          request = HTTP::Request.new("OPTIONS", "/poweredbylaunch")
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
          response.headers["X-Powered-By"].should eq "Launch"
          response.body.should contain "Hello World!"
        end
      end
    end
  end
end
