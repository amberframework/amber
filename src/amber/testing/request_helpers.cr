require "http"
require "./test_response"
require "./context_builder"

module Amber::Testing
  # Provides HTTP request helper methods for use in specs.
  # Include this module in your spec context to make requests
  # against the Amber application without starting a real server.
  #
  # Requests are routed through the Amber pipeline programmatically,
  # using the routes and pipes configured on Amber::Server.
  #
  # ```
  # describe "MyController" do
  #   include Amber::Testing::RequestHelpers
  #
  #   it "returns a list of items" do
  #     response = get("/items")
  #     response.status_code.should eq(200)
  #   end
  # end
  # ```
  module RequestHelpers
    # Send a GET request to the given path.
    def get(path : String, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("GET", path, body: nil, headers: headers)
    end

    # Send a POST request to the given path with an optional body.
    def post(path : String, body : String? = nil, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("POST", path, body: body, headers: headers)
    end

    # Send a PUT request to the given path with an optional body.
    def put(path : String, body : String? = nil, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("PUT", path, body: body, headers: headers)
    end

    # Send a PATCH request to the given path with an optional body.
    def patch(path : String, body : String? = nil, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("PATCH", path, body: body, headers: headers)
    end

    # Send a DELETE request to the given path.
    def delete(path : String, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("DELETE", path, body: nil, headers: headers)
    end

    # Send a HEAD request to the given path.
    def head(path : String, headers : HTTP::Headers? = nil) : TestResponse
      perform_request("HEAD", path, body: nil, headers: headers)
    end

    # Send a POST request with a JSON body.
    # Automatically sets the Content-Type header to application/json.
    def post_json(path : String, body) : TestResponse
      headers = HTTP::Headers{"Content-Type" => "application/json", "Accept" => "application/json"}
      perform_request("POST", path, body: body.to_json, headers: headers)
    end

    # Send a PUT request with a JSON body.
    # Automatically sets the Content-Type header to application/json.
    def put_json(path : String, body) : TestResponse
      headers = HTTP::Headers{"Content-Type" => "application/json", "Accept" => "application/json"}
      perform_request("PUT", path, body: body.to_json, headers: headers)
    end

    # Send a PATCH request with a JSON body.
    # Automatically sets the Content-Type header to application/json.
    def patch_json(path : String, body) : TestResponse
      headers = HTTP::Headers{"Content-Type" => "application/json", "Accept" => "application/json"}
      perform_request("PATCH", path, body: body.to_json, headers: headers)
    end

    # Perform an HTTP request through the Amber pipeline and return a TestResponse.
    private def perform_request(method : String, path : String, body : String? = nil, headers : HTTP::Headers? = nil) : TestResponse
      builder = ContextBuilder.new.method(method).path(path)
      builder = builder.body(body) if body
      if headers
        headers.each { |key, values| values.each { |value| builder = builder.header(key, value) } }
      end

      context, io = builder.build_with_io
      pipeline = Amber::Server.handler
      pipeline.prepare_pipelines
      pipeline.call(context)
      context.response.close

      io.rewind
      client_response = HTTP::Client::Response.from_io(io, decompress: false)
      TestResponse.from_client_response(client_response)
    end
  end
end
