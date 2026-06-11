require "json"
require "http"

module Amber::Testing
  # Wraps the result of an HTTP request made through the testing helpers.
  # Provides convenient methods for asserting status codes, parsing JSON,
  # and inspecting response headers and body content.
  class TestResponse
    getter status_code : Int32
    getter body : String
    getter headers : HTTP::Headers

    def initialize(@status_code : Int32, @body : String, @headers : HTTP::Headers)
    end

    # Build a TestResponse from a raw HTTP::Client::Response.
    def self.from_client_response(response : HTTP::Client::Response) : TestResponse
      new(
        status_code: response.status_code,
        body: response.body,
        headers: response.headers
      )
    end

    # Parse the response body as JSON.
    # Raises JSON::ParseException if the body is not valid JSON.
    def json : JSON::Any
      JSON.parse(body)
    end

    # Returns true if the status code is in the 2xx range.
    def successful? : Bool
      (200..299).includes?(status_code)
    end

    # Returns true if the status code is in the 3xx range.
    def redirect? : Bool
      (300..399).includes?(status_code)
    end

    # Returns true if the status code is in the 4xx range.
    def client_error? : Bool
      (400..499).includes?(status_code)
    end

    # Returns true if the status code is in the 5xx range.
    def server_error? : Bool
      (500..599).includes?(status_code)
    end

    # Returns the value of the Location header if present, nil otherwise.
    # Useful for checking redirect targets.
    def redirect_url : String?
      headers["Location"]?
    end

    # Returns the Content-Type header value if present, nil otherwise.
    def content_type : String?
      headers["Content-Type"]?
    end
  end
end
