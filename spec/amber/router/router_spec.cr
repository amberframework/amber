require "../../spec_helper"

module Amber
  module Router
    describe Router do
      describe "#resources" do
        it "defines all resources" do
          router = Router.new

          router.draw :web do
            resources "hello", HelloController
          end

          router.match("GET", "/hello").path.should eq "get/hello"
          router.match("HEAD", "/hello").path.should eq "head/hello"
          router.match("OPTIONS", "/hello").path.should eq "options/hello"
          router.match("GET", "/hello/2").path.should eq "get/hello/:id"
          router.match("HEAD", "/hello/2").path.should eq "head/hello/:id"
          router.match("OPTIONS", "/hello/2").path.should eq "options/hello/:id"
          router.match("GET", "/hello/new").path.should eq "get/hello/new"
          router.match("HEAD", "/hello/new").path.should eq "head/hello/new"
          router.match("OPTIONS", "/hello/new").path.should eq "options/hello/new"
          router.match("GET", "/hello/2/edit").path.should eq "get/hello/:id/edit"
          router.match("HEAD", "/hello/2/edit").path.should eq "head/hello/:id/edit"
          router.match("OPTIONS", "/hello/2/edit").path.should eq "options/hello/:id/edit"
          router.match("OPTIONS", "/hello/1").path.should eq "options/hello/:id"
          router.match("PUT", "/hello/1").path.should eq "put/hello/:id"
          router.match("PATCH", "/hello/1").path.should eq "patch/hello/:id"
          router.match("DELETE", "/hello/1").path.should eq "delete/hello/:id"
          router.match("POST", "/hello").path.should eq "post/hello"
          router.match(:GET, "/hello").path.should eq "get/hello"
          router.match(:get, "/hello").path.should eq "get/hello"
        end

        context "when specifying constraints" do
          it "uses constraints for defining crud routes" do
            router = Router.new
            router.draw :web do
              resources "/orders", HelloController, constraints: {"id" => /\d\d\d/}
            end

            # unchanged
            router.match("POST", "/orders").found?.should be_true
            router.match("GET", "/orders").found?.should be_true

            # would have matched without regex constraint
            router.match("GET", "/orders/abc").found?.should be_false
            router.match("GET", "/orders/def/edit").found?.should be_false
            router.match("PUT", "/orders/3ghifds").found?.should be_false
            router.match("PATCH", "/orders/3ghifds").found?.should be_false
            router.match("DELETE", "/orders/abb").found?.should be_false

            # will match due to constraints
            router.match("GET", "/orders/554").found?.should be_true
            router.match("GET", "/orders/511/edit").found?.should be_true
            router.match("PUT", "/orders/511").found?.should be_true
            router.match("PATCH", "/orders/511").found?.should be_true
            router.match("DELETE", "/orders/511").found?.should be_true
          end
        end

        context "when specifying actions" do
          it "defines only specified resources" do
            router = Router.new

            router.draw :web do
              resources "hello", HelloController, only: [:index, :update]
            end

            router.match("GET", "/hello").path.should eq "get/hello"
            router.match("GET", "/hello/2").found?.should be_false
            router.match("GET", "/hello/new").found?.should be_false
            router.match("GET", "/hello/2/edit").found?.should be_false
            router.match("PUT", "/hello/1").path.should eq "put/hello/:id"
            router.match("PATCH", "/hello/1").path.should eq "patch/hello/:id"
            router.match("DELETE", "/hello/1").found?.should be_false
          end

          it "defines resources excluding from list" do
            router = Router.new

            router.draw :web do
              resources "hello", HelloController, except: [:index, :update]
            end

            router.match("GET", "/hello").found?.should be_false
            router.match("GET", "/hello/2").path.should eq "get/hello/:id"
            router.match("GET", "/hello/new").path.should eq "get/hello/new"
            router.match("GET", "/hello/2/edit").path.should eq "get/hello/:id/edit"
            router.match("PUT", "/hello/1").found?.should be_false
            router.match("PATCH", "/hello/1").found?.should be_false
            router.match("DELETE", "/hello/1").path.should eq "delete/hello/:id"
          end
        end
      end

      describe "#route_defined?" do
        it "returns false when route is not drawn" do
          router = Router.new
          request = HTTP::Request.new("GET", "/products/world")

          router.route_defined?(request).should eq false
        end

        it "returns true when route exists" do
          router = Router.new
          request = HTTP::Request.new("GET", "/hello/world")

          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }

          route = Route.new("GET", "/hello/world", handler)
          router.add(route)

          router.route_defined?(request).should eq true
        end
      end

      describe "#draw" do
        it "registers a route" do
          router = Router.new
          request = HTTP::Request.new("GET", "/checkout/elias")

          router.draw :web do
            get "/checkout/:name", HelloController, :world
          end

          route = router.match_by_request(request)
          route.found?.should eq true
          route.path.should eq "get/checkout/:name"
        end

        it "registers routes with constraints as Hash" do
          router = Router.new
          router.draw :web do
            get "/checkout/:cart", HelloController, :world, {"cart" => /\d\d\d/}
          end

          request = HTTP::Request.new("GET", "/checkout/hello")
          route = router.match_by_request(request)
          route.found?.should eq false

          request = HTTP::Request.new("GET", "/checkout/he110")
          route = router.match_by_request(request)
          route.found?.should eq true
        end
      end

      describe "#match with a response extension in the path" do
        handler = ->(_context : HTTP::Server::Context) { }

        it "routes a path to the route that declares its extension, ahead of a catch-all" do
          router = Router.new
          router.add Route.new("GET", "/projects/:project_id/insights/overview.md", handler, :overview, :web, Scope.new, "InsightsController")
          router.add Route.new("GET", "/*", handler, :static, :web, Scope.new, "StaticController")

          route = router.match_by_request(HTTP::Request.new("GET", "/projects/7/insights/overview.md"))
          route.found?.should be_true
          route.payload.not_nil!.action.should eq :overview
          route.params["project_id"].should eq "7"
        end

        it "routes a declared extension route ahead of the same path without the extension" do
          router = Router.new
          router.add Route.new("GET", "/overview", handler, :overview_html, :web, Scope.new, "InsightsController")
          router.add Route.new("GET", "/overview.md", handler, :overview_md, :web, Scope.new, "InsightsController")

          router.match_by_request(HTTP::Request.new("GET", "/overview.md")).payload.not_nil!.action.should eq :overview_md
          router.match_by_request(HTTP::Request.new("GET", "/overview")).payload.not_nil!.action.should eq :overview_html
        end

        it "still strips the extension to match a parameterized route" do
          router = Router.new
          router.add Route.new("GET", "/users/:id", handler, :show, :web, Scope.new, "UsersController")

          route = router.match_by_request(HTTP::Request.new("GET", "/users/1.json"))
          route.found?.should be_true
          route.params["id"].should eq "1"
        end

        it "still strips the extension before a catch-all when no route declares it" do
          router = Router.new
          router.add Route.new("GET", "/report", handler, :report, :web, Scope.new, "ReportsController")
          router.add Route.new("GET", "/*", handler, :static, :web, Scope.new, "StaticController")

          router.match_by_request(HTTP::Request.new("GET", "/report.md")).payload.not_nil!.action.should eq :report
        end

        it "falls back to the full path when the stripped path matches nothing" do
          router = Router.new
          router.add Route.new("GET", "/files/*", handler, :download, :web, Scope.new, "FilesController")

          route = router.match_by_request(HTTP::Request.new("GET", "/files/report.json"))
          route.found?.should be_true
          route.payload.not_nil!.action.should eq :download
        end
      end

      describe "#add" do
        it "register a GET route" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }

          route = Route.new("GET", "/some/joe", handler)
          router.add(route)
        end

        it "correctly passes constraints from Route as Hash" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }

          route = Route.new("GET", "/posts/:slug", handler, :index, :web, Scope.new, "PostsController", {"slug" => /\d\d\-\w+/})
          router.add(route)

          request = HTTP::Request.new("GET", "/posts/hello")
          route = router.match_by_request(request)
          route.found?.should eq false

          request = HTTP::Request.new("GET", "/posts/55-hello")
          route = router.match_by_request(request)
          route.found?.should eq true
          route.path.should eq "get/posts/:slug"
        end
      end

      describe "#match_by_controller_action" do
        handler = ->(_context : HTTP::Server::Context) { }
        router = Router.new
        route_a = Route.new("GET", "/fake", handler, :index, :web, Scope.new, "FakeController")
        route_b = Route.new("GET", "/fake/new", handler, :new, :web, Scope.new, "FakeController")
        route_c = Route.new("GET", "/fake/:id", handler, :show, :web, Scope.new, "FakeController")
        route_d = Route.new("GET", "/another/:id", handler, :another, :web, Scope.new, "FakeController")

        router.add route_a
        router.add route_b
        router.add route_c
        router.add route_d

        it "matches route by controller and action" do
          router.match_by_controller_action(:fakecontroller, :index).should eq route_a
        end

        it "matches controller new action" do
          router.match_by_controller_action(:fakecontroller, :new).should eq route_b
        end

        it "matches controller show action" do
          router.match_by_controller_action(:fakecontroller, :show).should eq route_c
        end

        it "matches controller another action" do
          router.match_by_controller_action(:fakecontroller, :another).should eq route_d
        end
      end
    end
  end
end
