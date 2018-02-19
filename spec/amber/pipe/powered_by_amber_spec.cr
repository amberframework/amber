require "../../../spec_helper"

module Amber
  module Pipe
    describe PoweredByAmber do
      context "Adds X-Powered-By: Amber to response" do
        pipeline = Pipeline.new

        pipeline.build :web do
          plug PoweredByAmber.new
        end

        Amber::Server.router.draw :web do
          options "/poweredbyamber", HelloController, :world
        end

        pipeline.prepare_pipelines

        it "should contain X-Powered-By in response" do
          request = HTTP::Request.new("OPTIONS", "/poweredbyamber")
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
          response.headers["X-Powered-By"].should eq "Amber"
          response.body.should contain "Hello World!"
        end
      end
    end
  end
end
