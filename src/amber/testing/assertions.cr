require "./test_response"

module Amber::Testing
  # Custom assertion helpers for use in Crystal specs.
  # These complement the built-in `should` matchers with
  # domain-specific assertions for HTTP responses.
  #
  # ```
  # describe "API" do
  #   include Amber::Testing::Assertions
  #   include Amber::Testing::RequestHelpers
  #
  #   it "returns success" do
  #     response = get("/api/status")
  #     assert_response_status(response, 200)
  #     assert_response_success(response)
  #     assert_json_content_type(response)
  #   end
  # end
  # ```
  module Assertions
    # Assert that a TestResponse has the given status code.
    def assert_response_status(response : TestResponse, status : Int32)
      response.status_code.should eq(status)
    end

    # Assert that a TestResponse is successful (2xx).
    def assert_response_success(response : TestResponse)
      response.successful?.should be_true
    end

    # Assert that a TestResponse is a redirect (3xx).
    def assert_response_redirect(response : TestResponse)
      response.redirect?.should be_true
    end

    # Assert that a TestResponse is a redirect to the given URL.
    def assert_redirect_to(response : TestResponse, path : String)
      response.redirect?.should be_true
      response.redirect_url.should eq(path)
    end

    # Assert that a TestResponse is a client error (4xx).
    def assert_response_client_error(response : TestResponse)
      response.client_error?.should be_true
    end

    # Assert that a TestResponse is a not found error (404).
    def assert_response_not_found(response : TestResponse)
      response.status_code.should eq(404)
    end

    # Assert that a TestResponse is a server error (5xx).
    def assert_response_server_error(response : TestResponse)
      response.server_error?.should be_true
    end

    # Assert that the response Content-Type contains the expected type string.
    def assert_content_type(response : TestResponse, type : String)
      content_type = response.content_type
      content_type.should_not be_nil
      content_type.not_nil!.should contain(type)
    end

    # Assert that the response Content-Type is JSON.
    def assert_json_content_type(response : TestResponse)
      assert_content_type(response, "application/json")
    end

    # Assert that the response Content-Type is HTML.
    def assert_html_content_type(response : TestResponse)
      assert_content_type(response, "text/html")
    end

    # Assert that the response body contains the given string.
    def assert_body_contains(response : TestResponse, text : String)
      response.body.should contain(text)
    end

    # Assert that the response body is valid JSON and return the parsed result.
    def assert_json_body(response : TestResponse) : JSON::Any
      response.json
    end

    # Assert that a specific response header is present with the expected value.
    def assert_header(response : TestResponse, key : String, value : String)
      response.headers[key]?.should eq(value)
    end
  end
end
