require "../../spec_helper"

private def request_through_proxy(peer : String, headers : HTTP::Headers) : HTTP::Request
  request = HTTP::Request.new("GET", "/client_ip_address", headers)
  request.remote_address = Socket::IPAddress.new(peer, 54_321)
  request
end

module Amber
  module Pipe
    describe ClientIp do
      context "IP from headers" do
        before_each do
          Amber::Server.router.draw :web do
            get "/client_ip_address", HelloController, :client_ip_address
          end
        end

        it "takes the nearest untrusted X-Forwarded-For hop from a trusted proxy" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new
          end
          pipeline.prepare_pipelines

          spoofed_ip_address = "102.168.35.88"
          client_ip_address = "102.168.35.99"
          headers = HTTP::Headers.new
          headers["X-Forwarded-For"] = [spoofed_ip_address, client_ip_address]
          request = request_through_proxy("127.0.0.1", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain client_ip_address
          response.body.should_not contain spoofed_ip_address
        end

        it "uses the peer address when the peer is not a trusted proxy" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug ClientIp.new
          end
          pipeline.prepare_pipelines

          headers = HTTP::Headers{"X-Forwarded-For" => "102.168.35.88"}
          request = request_through_proxy("203.0.113.9", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain "203.0.113.9"
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
          request = request_through_proxy("127.0.0.1", headers)
          response = create_request_and_return_io(pipeline, request)
          response.body.should contain client_ip_address
        end
      end
    end
  end
end
