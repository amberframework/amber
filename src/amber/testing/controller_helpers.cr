require "http"
require "./context_builder"

module Amber::Testing
  # Provides helpers for testing individual controllers in isolation.
  # Include this module in spec contexts where you want to build
  # controller instances and make assertions about their responses.
  #
  # ```
  # include Amber::Testing::ControllerHelpers
  #
  # describe MyController do
  #   it "returns the expected content" do
  #     controller = build_controller_context(MyController, :index)
  #     controller.index.should eq("expected content")
  #   end
  # end
  # ```
  module ControllerHelpers
    # Build a test context suitable for creating a controller.
    # Returns an HTTP::Server::Context configured with the given
    # method, path, headers, and query parameters.
    def build_test_context(method : String = "GET", path : String = "/",
                           headers : HTTP::Headers = HTTP::Headers.new,
                           params : Hash(String, String) = {} of String => String) : HTTP::Server::Context
      builder = ContextBuilder.new
        .method(method)
        .path(path)

      params.each do |key, value|
        builder = builder.query_param(key, value)
      end

      headers.each do |key, values|
        values.each do |value|
          builder = builder.header(key, value)
        end
      end

      builder.build
    end

    # Build a controller instance with a test context.
    # This is a macro because the controller class must be known at compile time.
    #
    # ```
    # controller = build_controller(MyController, "GET", "/items")
    # controller.index.should eq("items list")
    # ```
    macro build_controller(controller_class, action = :index, method = "GET", path = "/")
      %context = Amber::Testing::ContextBuilder.new
        .method({{method}})
        .path({{path}})
        .build
      {{controller_class}}.new(%context)
    end

    # Assert that the given controller's response has the expected status code.
    def assert_controller_response(controller : Amber::Controller::Base, status : Int32)
      controller.response.status_code.should eq(status)
    end

    # Assert that the given controller's response is a redirect to the expected path.
    def assert_controller_redirect_to(controller : Amber::Controller::Base, path : String)
      controller.response.headers["Location"]?.should eq(path)
      (300..399).includes?(controller.response.status_code).should be_true
    end

    # Assert that the given controller's response has the expected Content-Type.
    def assert_controller_content_type(controller : Amber::Controller::Base, type : String)
      content_type = controller.response.headers["Content-Type"]?
      content_type.should_not be_nil
      content_type.not_nil!.should contain(type)
    end
  end
end
