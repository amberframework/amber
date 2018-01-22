require "../../../../spec_helper"

module Amber
  module Pipe
    describe ClientIp do
      context "Gets client IP from headers" do

        Amber::Server.router.draw :web do
          get "/client_ip_address", HelloController, :client_ip_address
        end

        it "gets last client IP from default header" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new
          end
          pipeline.prepare_pipelines

          ip_address1 = "102.168.35.88"
          ip_address2 = "102.168.35.99"
          headers = HTTP::Headers.new
          headers["X-Forwarded-For"] = [ip_address1, ip_address2]
          request = HTTP::Request.new("GET", "/client_ip_address", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain ip_address2
        end

        it "gets client IP from first custom header found" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new(["X-Unmatched", "X-Client-IP"])
          end
          pipeline.prepare_pipelines

          ip_address1 = "102.168.35.88"
          ip_address2 = "102.168.35.99"
          headers = HTTP::Headers.new
          headers["X-Forwarded-For"] = ip_address1
          headers["X-Client-IP"] = ip_address2
          request = HTTP::Request.new("GET", "/client_ip_address", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain ip_address2
        end
      end
    end
  end
end
