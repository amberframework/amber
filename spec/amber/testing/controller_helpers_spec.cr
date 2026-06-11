require "../../spec_helper"
require "../../../src/amber/testing"

# Test controller for controller helper specs
class ControllerTestTarget < Amber::Controller::Base
  def index
    "Index"
  end

  def show
    "Show"
  end

  def create
    response.status_code = 201
    response.headers["Content-Type"] = "application/json"
    %({"id": 1, "created": true})
  end

  def redirect_example
    redirect_to "/login"
  end
end

# A helper class that includes the module so we can use macros
# without polluting the global namespace.
class ControllerTestRunner
  include Amber::Testing::ControllerHelpers

  def self.run_build_controller_index
    runner = new
    runner.build_index
  end

  def self.run_build_controller_create
    runner = new
    runner.build_create
  end

  def self.run_build_controller_show
    runner = new
    runner.build_show
  end

  def self.run_build_controller_redirect
    runner = new
    runner.build_redirect
  end

  def build_index
    build_controller(ControllerTestTarget, :index)
  end

  def build_create
    build_controller(ControllerTestTarget, :create, method: "POST")
  end

  def build_show
    build_controller(ControllerTestTarget, :show, path: "/items/42")
  end

  def build_redirect
    build_controller(ControllerTestTarget, :redirect_example)
  end
end

module ControllerHelpersAssertions
  extend Amber::Testing::ControllerHelpers
end

describe Amber::Testing::ControllerHelpers do
  describe "build_controller" do
    it "creates a controller instance with a test context" do
      controller = ControllerTestRunner.run_build_controller_index
      controller.should be_a(ControllerTestTarget)
    end

    it "creates a controller that can execute actions" do
      controller = ControllerTestRunner.run_build_controller_index
      result = controller.index
      result.should eq("Index")
    end

    it "creates a controller with custom method" do
      controller = ControllerTestRunner.run_build_controller_create
      controller.request.method.should eq("POST")
    end

    it "creates a controller with custom path" do
      controller = ControllerTestRunner.run_build_controller_show
      controller.request.path.should eq("/items/42")
    end
  end

  describe "#build_test_context" do
    it "creates a context with default values" do
      context = ControllerHelpersAssertions.build_test_context
      context.request.method.should eq("GET")
      context.request.path.should eq("/")
    end

    it "creates a context with custom method and path" do
      context = ControllerHelpersAssertions.build_test_context(method: "POST", path: "/users")
      context.request.method.should eq("POST")
      context.request.path.should eq("/users")
    end
  end

  describe "#assert_controller_response" do
    it "passes when status code matches" do
      controller = ControllerTestRunner.run_build_controller_create
      controller.create
      ControllerHelpersAssertions.assert_controller_response(controller, 201)
    end
  end

  describe "#assert_controller_content_type" do
    it "passes when content type matches" do
      controller = ControllerTestRunner.run_build_controller_create
      controller.create
      ControllerHelpersAssertions.assert_controller_content_type(controller, "application/json")
    end
  end

  describe "#assert_controller_redirect_to" do
    it "passes when redirect location matches" do
      controller = ControllerTestRunner.run_build_controller_redirect
      controller.redirect_example
      ControllerHelpersAssertions.assert_controller_redirect_to(controller, "/login")
    end
  end
end
