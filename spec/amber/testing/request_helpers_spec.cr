require "../../spec_helper"
require "../../../src/amber/testing"

# Test controller for request helper specs
class TestRequestController < Amber::Controller::Base
  def index
    "Index Response"
  end

  def show
    "Show Response"
  end

  def create
    "Create Response"
  end

  def update
    "Update Response"
  end

  def destroy
    "Destroy Response"
  end

  def json_echo
    context.response.headers["Content-Type"] = "application/json"
    %({"received": true})
  end

  def redirect_action
    redirect_to "/destination"
  end
end

module RequestHelpersSpec
  extend Amber::Testing::RequestHelpers

  describe Amber::Testing::RequestHelpers do
    # Routes are drawn in before_all (not at file load) because the router is
    # global mutable state: specs that reconfigure the server at runtime wipe
    # load-time routes, making these specs fail under other spec-file orders.
    before_all do
      Amber::Server.router.draw :web do
        get "/test", TestRequestController, :index
        get "/test/json", TestRequestController, :json_echo
        get "/test/redirect", TestRequestController, :redirect_action
        get "/test/:id", TestRequestController, :show
        post "/test", TestRequestController, :create
        put "/test/:id", TestRequestController, :update
        patch "/test/:id", TestRequestController, :update
        delete "/test/:id", TestRequestController, :destroy
      end

      Amber::Server.handler.build(:web) { }
    end
    describe "#get" do
      it "makes a GET request and returns a TestResponse" do
        response = RequestHelpersSpec.get("/test")
        response.should be_a(Amber::Testing::TestResponse)
        response.status_code.should eq(200)
        response.body.should eq("Index Response")
      end

      it "handles route params" do
        response = RequestHelpersSpec.get("/test/42")
        response.status_code.should eq(200)
        response.body.should eq("Show Response")
      end

      it "handles custom headers" do
        headers = HTTP::Headers{"Accept" => "application/json"}
        response = RequestHelpersSpec.get("/test", headers: headers)
        response.status_code.should eq(200)
      end

      it "returns 404 for unknown routes" do
        response = RequestHelpersSpec.get("/nonexistent")
        response.status_code.should eq(404)
      end
    end

    describe "#post" do
      it "makes a POST request" do
        response = RequestHelpersSpec.post("/test")
        response.status_code.should eq(200)
        response.body.should eq("Create Response")
      end

      it "sends a body" do
        response = RequestHelpersSpec.post("/test", body: "some data")
        response.status_code.should eq(200)
      end
    end

    describe "#put" do
      it "makes a PUT request" do
        response = RequestHelpersSpec.put("/test/1")
        response.status_code.should eq(200)
        response.body.should eq("Update Response")
      end
    end

    describe "#patch" do
      it "makes a PATCH request" do
        response = RequestHelpersSpec.patch("/test/1")
        response.status_code.should eq(200)
        response.body.should eq("Update Response")
      end
    end

    describe "#delete" do
      it "makes a DELETE request" do
        response = RequestHelpersSpec.delete("/test/1")
        response.status_code.should eq(200)
        response.body.should eq("Destroy Response")
      end
    end

    describe "#post_json" do
      it "sends JSON with appropriate headers" do
        response = RequestHelpersSpec.post_json("/test", {name: "Alice"})
        response.status_code.should eq(200)
      end
    end

    describe "#put_json" do
      it "sends JSON with appropriate headers" do
        response = RequestHelpersSpec.put_json("/test/1", {name: "Updated"})
        response.status_code.should eq(200)
      end
    end

    describe "redirect responses" do
      it "detects redirects" do
        response = RequestHelpersSpec.get("/test/redirect")
        response.redirect?.should be_true
        response.redirect_url.should eq("/destination")
      end
    end
  end
end
