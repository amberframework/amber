require "../../spec_helper"

# Use a fresh router for named route tests to avoid conflicts
module Amber::Router
  describe NamedRoutes do
    # Register test routes before running specs.
    # Use before_all so routes are registered on the live router instance even
    # if another spec (e.g. dsl/server_spec.cr) called Amber::Server.reset_instance
    # earlier in the suite run.
    before_all do
      Amber::Server.router.draw :web do
        get "/named_users", HelloController, :index, route_name: :named_users
        get "/named_users/:id", HelloController, :show, route_name: :named_user
        get "/named_users/:id/edit", HelloController, :edit, route_name: :edit_named_user
        get "/named_users/new", HelloController, :new, route_name: :new_named_user
        post "/named_users", HelloController, :create, route_name: :create_named_user
      end
    end

    describe ".path" do
      it "generates a simple path without params" do
        NamedRoutes.path(:named_users).should eq "/named_users"
      end

      it "substitutes path parameters" do
        NamedRoutes.path(:named_user, id: "5").should eq "/named_users/5"
      end

      it "substitutes multiple path parameters" do
        # Register a route with multiple params for this test
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/orgs/:org_id/members/:id", handler, :show, :web,
          Scope.new, "MemberController", {} of String => Regex, :org_member)
        Amber::Server.router.add(route)

        NamedRoutes.path(:org_member, org_id: "42", id: "7").should eq "/orgs/42/members/7"
      end

      it "appends extra params as query string" do
        path = NamedRoutes.path(:named_users, page: "2", per: "10")
        path.should contain("/named_users?")
        path.should contain("page=2")
        path.should contain("per=10")
      end

      it "raises for unknown route name" do
        expect_raises(Exception, "No route named :nonexistent_route") do
          NamedRoutes.path(:nonexistent_route)
        end
      end
    end

    describe ".url" do
      it "generates a full URL with host" do
        url = NamedRoutes.url(:named_users)
        url.should contain("://")
        url.should end_with("/named_users")
      end

      it "generates a full URL with path parameters" do
        url = NamedRoutes.url(:named_user, id: "5")
        url.should contain("://")
        url.should end_with("/named_users/5")
      end
    end
  end
end
