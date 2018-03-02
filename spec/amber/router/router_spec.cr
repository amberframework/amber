require "../../../spec_helper"

module Amber
  module Router
    describe Router do
      describe "#resources" do
        it "defines all resources" do
          router = Router.new

          router.draw :web do
            resources "/hello", HelloController
          end

          router.match("GET", "/hello").path.should eq "get/hello"
          router.match("GET", "/hello/2").path.should eq "get/hello/:id"
          router.match("GET", "/hello/new").path.should eq "get/hello/new"
          router.match("GET", "/hello/2/edit").path.should eq "get/hello/:id/edit"
          router.match("PUT", "/hello/1").path.should eq "put/hello/:id"
          router.match("PATCH", "/hello/1").path.should eq "patch/hello/:id"
          router.match("DELETE", "/hello/1").path.should eq "delete/hello/:id"
          router.match("POST", "/hello").path.should eq "post/hello"
        end

        context "when specifying actions" do
          it "defines only specified resources" do
            router = Router.new

            router.draw :web do
              resources "/hello", HelloController, only: [:index, :update]
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
              resources "/hello", HelloController, except: [:index, :update]
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
      end

      describe "#match_by_controller_action" do
        handler = ->(context : HTTP::Server::Context) {}
        router = Router.new
        route_a = Route.new("GET", "/fake", handler, :index, :web, "", "FakeController")
        route_b = Route.new("GET", "/fake/new", handler, :new, :web, "", "FakeController")
        route_c = Route.new("GET", "/fake/:id", handler, :show, :web, "", "FakeController")
        route_d = Route.new("GET", "/another/:id", handler, :another, :web, "", "FakeController")

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
