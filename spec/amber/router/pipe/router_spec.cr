require "../../../../spec_helper"

module Amber
  module Pipe
    describe Router do
      describe "#call" do
        it "raises exception when route not found" do
          router = Router.instance
          request = HTTP::Request.new("GET", "/bad/route")

          expect_raises Exceptions::RouteNotFound do
            create_request_and_return_io(router, request)
          end
        end

        it "routes" do
          router = Router.instance
          request = HTTP::Request.new("GET", "/index/elias")

          router.draw :web do
            get "/index/:name", HelloController, :world
          end

          response = create_request_and_return_io(router, request)

          response.body.should eq "Hello World!"
        end
      end

      describe "#route_defined?" do
        it "returns false when route is not drawn" do
          router = Router.instance
          request = HTTP::Request.new("GET", "/products/world")

          router.route_defined?(request).should eq false
        end

        it "returns true when route exists" do
          router = Router.instance
          request = HTTP::Request.new("GET", "/hello/world")

          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }

          route = Route.new("GET", "/hello/world", handler)
          router.add(route)

          router.route_defined?(request).should eq true
        end
      end

      describe "#draw" do
        it "registers a route" do
          router = Router.instance
          request = HTTP::Request.new("GET", "/checkout/elias")

          router.draw :web do
            get "/checkout/:name", HelloController, :world
          end

          route = Router.instance.match_by_request(request)
          route.found?.should eq true
          route.payload.verb.should eq "GET"
        end
      end

      describe "#add" do
        it "register a GET route" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }

          route = Route.new("GET", "/some/joe", handler)

          node = router.add(route)

          node.class.should eq Radix::Node(Amber::Route)
        end

        it "raises Amber::Exceptions::DuplicateRouteError on duplicate" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }
          route = Route.new("GET", "/some/joe", handler)

          router.add(route)

          expect_raises Amber::Exceptions::DuplicateRouteError do
            router.add(route)
          end
        end
      end
    end
  end
end
