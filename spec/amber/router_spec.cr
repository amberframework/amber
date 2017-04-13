require "./../spec_helper"

class HelloController < Amber::Controller
    def index; end
    def world; end
end

module Amber
    describe Router do

        describe "#draw" do
            it "registers a route" do
                router = Amber::Router.instance
                instance = HelloController.new
                world = ->instance.world

                Amber::Router.draw do
                    get "/hello/:world", :hello, :world
                end

                route = Amber::Router.instance.match(:GET, "/hello/:world")
                puts route.inspect
                puts route
                route.verb
                route.should_not eq :not_found
                route.class.should eq Route
            end
        end

        describe "#add" do
            it "register a GET route" do
                router = Router.new
                instance = HelloController.new
                world = ->instance.world
                route = Route.new(:GE, "/some/joe", instance, world)

                node = router.add(route)

                node.class.should eq Radix::Node(Amber::Route)
            end

            it "raises Amber::Exceptions::DuplicateRouteError. on duplicate" do
                router = Router.new
                instance = HelloController.new
                world = ->instance.world
                route = Route.new(:GET, "/some/joe", instance, world)

                router.add(route)


                expect_raises Amber::Exceptions::DuplicateRouteError do
                    router.add(route)
                end
            end
        end

        describe "#match" do
            it "finds a route by http_verb and path" do
                router = Router.new
                instance = HelloController.new
                world = ->instance.world
                route = Route.new(:Get, "/some/joe", instance, world)
                router.add(route)

                route = router.match(:GET, "/some/joe")

                route.class.should eq Route
            end
        end
    end
end
