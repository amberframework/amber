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

          router.match("GET", "/hello").key.should eq "get/hello"
          router.match("GET", "/hello/2").key.should eq "get/hello/:id"
          router.match("GET", "/hello/new").key.should eq "get/hello/new"
          router.match("GET", "/hello/2/edit").key.should eq "get/hello/:id/edit"
          router.match("PUT", "/hello/1").key.should eq "get/helloput/hello/:id"
          router.match("PATCH", "/hello/1").key.should eq "get/hellopatch/hello/:id"
          router.match("DELETE", "/hello/1").key.should eq "get/hellodelete/hello/:id"
          router.match("POST", "/hello").key.should eq "get/hellopost/hello"
        end

        context "when specifying actions" do
          it "defines only specified resources" do
            router = Router.new

            router.draw :web do
              resources "/hello", HelloController, only: [:index, :update]
            end

            router.match("GET", "/hello").key.should eq "get/hello"
            router.match("GET", "/hello/2").key.should eq ""
            router.match("GET", "/hello/new").key.should eq ""
            router.match("GET", "/hello/2/edit").key.should eq ""
            router.match("PUT", "/hello/1").key.should eq "get/helloput/hello/:id"
            router.match("PATCH", "/hello/1").key.should eq "get/hellopatch/hello/:id"
            router.match("DELETE", "/hello/1").key.should eq ""
          end

          it "defines resources excluding from list" do
            router = Router.new

            router.draw :web do
              resources "/hello", HelloController, except: [:index, :update]
            end

            router.match("GET", "/hello").key.should eq "get/hello/"
            router.match("GET", "/hello/2").key.should eq "get/hello/:id"
            router.match("GET", "/hello/new").key.should eq "get/hello/new"
            router.match("GET", "/hello/2/edit").key.should eq "get/hello/:id/edit"
            router.match("PUT", "/hello/1").key.should eq "get/hello/:id"
            router.match("PATCH", "/hello/1").key.should eq "get/hello/:id"
            router.match("DELETE", "/hello/1").key.should eq "get/hello/delete/hello/:id"
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
          route.payload.verb.should eq "GET"
        end
      end

      describe "#add" do
        it "register a GET route" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }

          route = Route.new("GET", "/some/joe", handler)

          node = router.add(route)

          node.class.should eq Radix::Node(Amber::Route)
        end

        it "raises Amber::Exceptions::DuplicateRouteError on duplicate" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }
          route = Route.new("GET", "/some/joe", handler)

          router.add(route)

          expect_raises Amber::Exceptions::DuplicateRouteError do
            router.add(route)
          end
        end
      end

      describe "#match_by_controller_action" do
        it "matches route by controller and action" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {}
          routeA = Route.new("GET", "/fake", handler, :index, :web, "", "FakeController")
          route = Route.new("GET", "/fake/route", handler, :route, :web, "", "FakeController")
          router.add routeA
          router.add route

          router.match_by_controller_action("fake", :route).should eq route
        end
      end

      describe "#all" do
        it "gets all routes defined" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context) {
            context.content = "hey world"
          }
          routes = [Route.new("GET", "/", handler),
                    Route.new("GET", "/a", handler),
                    Route.new("DELETE", "/b", handler),
                    Route.new("PUT", "/b/c", handler),
                    Route.new("POST", "/b/c/d", handler),
                    Route.new("GET", "/e/f", handler)]
          routes.each { |r| router.add r }

          router.draw :web do
            resources "/comments", HelloController
          end

          router.all.size.should eq 14
        end
      end
    end
  end
end
