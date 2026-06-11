require "../../spec_helper"

module Amber
  module Router
    describe Router do
      describe "#all_routes" do
        it "returns an empty array when no routes are registered" do
          router = Router.new
          router.all_routes.should be_empty
        end

        it "returns RouteInfo structs for registered routes" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          route = Route.new("GET", "/users", handler, :index, :web, Scope.new, "UserController")
          router.add(route)

          routes = router.all_routes
          routes.size.should eq 1
          routes.first.verb.should eq "GET"
          routes.first.path.should eq "/users"
          routes.first.controller.should eq "UserController"
          routes.first.action.should eq "index"
          routes.first.valve.should eq "web"
        end

        it "includes named routes with their names" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          route = Route.new("GET", "/users", handler, :index, :web, Scope.new, "UserController", {} of String => Regex, :users)
          router.add(route)

          routes = router.all_routes
          routes.first.name.should eq "users"
        end

        it "returns routes sorted by path" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          router.add(Route.new("GET", "/zebra", handler, :index, :web, Scope.new, "ZebraController"))
          router.add(Route.new("GET", "/alpha", handler, :index, :web, Scope.new, "AlphaController"))

          routes = router.all_routes
          routes.first.path.should eq "/alpha"
          routes.last.path.should eq "/zebra"
        end

        it "includes constraint information" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          route = Route.new("GET", "/posts/:slug", handler, :show, :web, Scope.new, "PostController", {"slug" => /\w+/})
          router.add(route)

          routes = router.all_routes
          routes.first.constraints["slug"].should eq "(?-imsx:\\w+)"
        end
      end

      describe "#route_table" do
        it "returns a formatted string with headers" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          route = Route.new("GET", "/users", handler, :index, :web, Scope.new, "UserController")
          router.add(route)

          table = router.route_table
          table.should contain("Verb")
          table.should contain("Path")
          table.should contain("Controller#Action")
          table.should contain("Pipe")
          table.should contain("Name")
          table.should contain("/users")
          table.should contain("UserController#index")
        end
      end

      describe "#match_by_name" do
        it "returns nil for unknown route names" do
          router = Router.new
          router.match_by_name(:nonexistent).should be_nil
        end

        it "returns the route for a known name" do
          router = Router.new
          handler = ->(_context : HTTP::Server::Context) { }

          route = Route.new("GET", "/users", handler, :index, :web, Scope.new, "UserController", {} of String => Regex, :users)
          router.add(route)

          found = router.match_by_name(:users)
          found.should_not be_nil
          found.not_nil!.action.should eq :index
          found.not_nil!.controller.should eq "UserController"
        end
      end
    end
  end
end

module Amber
  describe Route do
    describe "#name" do
      it "defaults to nil" do
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/users", handler)
        route.name.should be_nil
      end

      it "stores a named symbol" do
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/users", handler, :index, :web, Router::Scope.new, "UserController", {} of String => Regex, :users)
        route.name.should eq :users
      end
    end

    describe "#to_json with name" do
      it "includes name when present" do
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/users", handler, :index, :web, Router::Scope.new, "UserController", {} of String => Regex, :users)
        json = route.to_json
        parsed = JSON.parse(json)
        parsed["name"].should eq "users"
      end

      it "omits name when nil" do
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/users", handler)
        json = route.to_json
        parsed = JSON.parse(json)
        parsed["name"]?.should be_nil
      end
    end
  end
end

module Amber
  describe Server do
    describe ".all_routes" do
      it "delegates to router.all_routes" do
        routes = Amber::Server.all_routes
        routes.should be_a(Array(Router::RouteInfo))
      end
    end
  end
end
