require "../../spec_helper"

module Amber::Router
  describe RouteInfo do
    describe "#to_s" do
      it "formats route info as a readable string" do
        info = RouteInfo.new(
          verb: "GET",
          path: "/users/:id",
          controller: "UserController",
          action: "show",
          valve: "web",
          scope: "",
          name: "user"
        )
        output = info.to_s
        output.should contain("GET")
        output.should contain("/users/:id")
        output.should contain("UserController#show")
        output.should contain("web")
        output.should contain("user")
      end

      it "handles nil name" do
        info = RouteInfo.new(
          verb: "POST",
          path: "/users",
          controller: "UserController",
          action: "create",
          valve: "web",
          scope: ""
        )
        output = info.to_s
        output.should contain("POST")
        output.should contain("/users")
        output.should contain("UserController#create")
      end
    end

    describe "#to_json" do
      it "serializes all fields to JSON" do
        info = RouteInfo.new(
          verb: "GET",
          path: "/users/:id",
          controller: "UserController",
          action: "show",
          valve: "web",
          scope: "/api",
          name: "user",
          constraints: {"id" => "\\d+"}
        )
        json = info.to_json
        parsed = JSON.parse(json)
        parsed["verb"].should eq "GET"
        parsed["path"].should eq "/users/:id"
        parsed["controller"].should eq "UserController"
        parsed["action"].should eq "show"
        parsed["valve"].should eq "web"
        parsed["scope"].should eq "/api"
        parsed["name"].should eq "user"
        parsed["constraints"]["id"].should eq "\\d+"
      end

      it "serializes nil name as null" do
        info = RouteInfo.new(
          verb: "GET",
          path: "/users",
          controller: "UserController",
          action: "index",
          valve: "web",
          scope: ""
        )
        json = info.to_json
        parsed = JSON.parse(json)
        parsed["name"]?.try(&.raw).should be_nil
      end
    end
  end
end
