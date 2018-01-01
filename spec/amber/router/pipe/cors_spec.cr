require "../../../../spec_helper"

module Amber
  module Pipe
    describe CORS do
      context "allowed headers" do
        pipeline = Pipeline.new

        pipeline.build :cors do
          plug CORS.new
        end

        Amber::Server.router.draw :cors do
          options "/test", HelloController, :world
        end

        pipeline.prepare_pipelines

        it "should allow a case-insensitive header values" do
          cors = CORS.new
          request = HTTP::Request.new("OPTIONS", "/test")
          request.headers["Access-Control-Request-Method"] = "OPTIONS"
          request.headers["Access-Control-Request-Headers"] = "cOnTeNt-TyPe"
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
        end
      end
    end
  end
end
