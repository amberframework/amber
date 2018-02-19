require "../../../spec_helper"

module Amber
  module Pipe
    describe ClientIp do
      context "IP from headers" do
        Amber::Server.router.draw :web do
          get "/client_ip_address", HelloController, :client_ip_address
        end

        it "gets first client IP from default header" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new
          end
          pipeline.prepare_pipelines

          client_ip_address = "102.168.35.88"
          proxy_1_ip_address = "102.168.35.99"
          proxy_2_ip_address = "102.168.35.100"
          headers = HTTP::Headers.new
          headers["X-Forwarded-For"] = [client_ip_address, proxy_1_ip_address, proxy_2_ip_address]
          request = HTTP::Request.new("GET", "/client_ip_address", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain client_ip_address
        end

        it "gets client IP from first custom header found" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new(["X-Unmatched", "X-Client-IP"])
          end
          pipeline.prepare_pipelines

          spoofed_ip_address = "102.168.35.88"
          client_ip_address = "102.168.35.99"
          headers = HTTP::Headers.new
          headers["X-Forwarded-For"] = spoofed_ip_address
          headers["X-Client-IP"] = client_ip_address
          request = HTTP::Request.new("GET", "/client_ip_address", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain client_ip_address
        end
      end
    end
  end
end
