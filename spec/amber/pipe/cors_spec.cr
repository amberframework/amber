require "../../../spec_helper"

module Amber
  module Pipe
    describe CORS do
      context "allowed headers" do
        # Pipeline with default settings
        pipeline = Pipeline.new
        pipeline.build :cors do
          plug CORS.new
        end
        pipeline.prepare_pipelines

        # Pipeline with custom settings
        pipeline_custom = Pipeline.new
        pipeline_custom.build :cors do
          plug CORS.new(allow_headers: "max-age")
        end
        pipeline_custom.prepare_pipelines

        Amber::Server.router.draw :cors do
          options "/test", HelloController, :world
        end

        it "should allow a case-insensitive header values" do
          request = HTTP::Request.new("OPTIONS", "/test")
          request.headers["Access-Control-Request-Method"] = "OPTIONS"
          request.headers["Access-Control-Request-Headers"] = "cOnTeNt-TyPe"
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
        end

        it "allows headers 'accept, content-type' by default" do
          request = HTTP::Request.new("OPTIONS", "/test")
          request.headers["Access-Control-Request-Method"] = "OPTIONS"
          request.headers["Access-Control-Request-Headers"] = "accept"
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
          response.headers["Access-Control-Allow-Headers"].should eq "accept, content-type"
        end

        it "can override settings at initialization" do
          request = HTTP::Request.new("OPTIONS", "/test")
          request.headers["Access-Control-Request-Method"] = "OPTIONS"
          request.headers["Access-Control-Request-Headers"] = "max-age"
          response = create_request_and_return_io(pipeline_custom, request)

          response.status_code.should eq 200
          response.headers["Access-Control-Allow-Headers"].should eq "max-age"
        end
      end
    end
  end
end
