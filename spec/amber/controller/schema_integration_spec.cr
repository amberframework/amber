require "../../spec_helper"

describe "Amber::Controller Schema Integration" do
  describe "backward compatibility" do
    it "still allows access to original params validation" do
      # Create a test request context
      request = HTTP::Request.new("GET", "/test?name=John&age=30")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      # Create a test controller
      controller = TestController.new(context)

      # Should be able to access params through query parameters
      controller.params["name"].should eq "John"
      controller.params["age"].should eq "30"
    end
  end

  describe "Schema API integration" do
    it "provides access to Schema validation methods" do
      request = HTTP::Request.new("POST", "/test")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      controller = TestController.new(context)

      # Should have Schema integration methods
      controller.responds_to?(:request_data).should be_true
      controller.responds_to?(:validation_result).should be_true
      controller.responds_to?(:validated_params).should be_true
      controller.responds_to?(:validation_failed?).should be_true
      controller.responds_to?(:respond_with).should be_true
      controller.responds_to?(:respond_with_error).should be_true
    end

    it "can merge request data from multiple sources" do
      request = HTTP::Request.new("POST", "/test?query=value")
      request.headers["Content-Type"] = "application/json"
      request.body = IO::Memory.new("{\"body\":\"data\"}")

      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      controller = TestController.new(context)

      # Test merging data (this should work with query params and body)
      merged_data = controller.merge_request_data

      # Should include query params
      merged_data["query"]?.should_not be_nil
      merged_data["query"].as_s.should eq "value"

      # Should include body data
      merged_data["body"]?.should_not be_nil
      merged_data["body"].as_s.should eq "data"
    end
  end
end

# Test controller that includes Schema integration
class TestController < Amber::Controller::Base
  # Make protected methods public for testing
  def params
    super
  end

  def merge_request_data
    super
  end

  def test
    "test action"
  end
end
