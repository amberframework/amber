require "../../spec_helper"

private def request_with(headers : HTTP::Headers) : HTTP::Request
  HTTP::Request.new("GET", "/posts/new", headers)
end

private def fetch_metadata(site : String, mode : String, dest : String) : HTTP::Headers
  HTTP::Headers{"Sec-Fetch-Site" => site, "Sec-Fetch-Mode" => mode, "Sec-Fetch-Dest" => dest}
end

module Amber::Pipe
  describe BreachGuard do
    describe ".may_compress_response_to?" do
      context "with Sec-Fetch-Site" do
        it "compresses same-origin, same-site and user-initiated (none) requests" do
          {"same-origin", "same-site", "none", "Same-Origin"}.each do |site|
            BreachGuard.may_compress_response_to?(request_with(fetch_metadata(site, "no-cors", "image"))).should be_true
          end
        end

        it "compresses a cross-site top-level page load" do
          BreachGuard.may_compress_response_to?(request_with(fetch_metadata("cross-site", "navigate", "document"))).should be_true
        end

        it "refuses a cross-site iframe, subresource or fetch" do
          {
            {"navigate", "iframe"},
            {"no-cors", "image"},
            {"no-cors", "script"},
            {"cors", "empty"},
            {"navigate", "frame"},
          }.each do |mode, dest|
            BreachGuard.may_compress_response_to?(request_with(fetch_metadata("cross-site", mode, dest))).should be_false
          end
        end

        it "refuses a cross-site request that names no mode or destination" do
          BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Sec-Fetch-Site" => "cross-site"})).should be_false
        end

        it "refuses a value it does not know" do
          BreachGuard.may_compress_response_to?(request_with(fetch_metadata("elsewhere", "navigate", "document"))).should be_false
        end

        it "decides by Sec-Fetch-Site even when a foreign Referer is present" do
          headers = fetch_metadata("same-origin", "cors", "empty")
          headers["Host"] = "example.com"
          headers["Referer"] = "https://attacker.example/"
          BreachGuard.may_compress_response_to?(request_with(headers)).should be_true
        end
      end

      context "without Sec-Fetch-Site" do
        it "compresses a request with no Referer" do
          BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Host" => "example.com"})).should be_true
        end

        it "compresses a request whose Referer has the request's own host and port" do
          {
            {"example.com", "https://example.com/posts"},
            {"EXAMPLE.com", "https://example.com/"},
            {"localhost:4460", "https://localhost:4460/posts?page=2"},
            {"example.com:443", "https://example.com/"},
            {"[::1]:8443", "https://[::1]:8443/"},
          }.each do |host, referer|
            BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Host" => host, "Referer" => referer})).should be_true
          end
        end

        it "refuses a Referer from another host or port" do
          {
            {"example.com", "https://google.com/"},
            {"example.com", "https://example.com.attacker.example/"},
            {"localhost:4460", "https://localhost:4461/"},
            {"example.com", "http://example.com:8080/"},
          }.each do |host, referer|
            BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Host" => host, "Referer" => referer})).should be_false
          end
        end

        it "refuses a Referer it cannot compare: no Host, or no host in the Referer" do
          BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Referer" => "https://example.com/"})).should be_false
          BreachGuard.may_compress_response_to?(request_with(HTTP::Headers{"Host" => "example.com", "Referer" => "/relative"})).should be_false
        end
      end
    end
  end
end
