require "radix"
require "http"

module Amber
    class Router
        HTTP_METHODS = %w(GET PUT POST DELETE OPTIONS HEAD CONNECT)

        getter :routes

        def self.instance
            @@router ||= new
        end

        def initialize
            @routes = Radix::Tree(Route).new
        end

        # This registers all the routes for the application
        def self.draw(&block)
            block.call
        end

        def match(http_verb, path) : Route | Symbol
            node = @routes.find build_node(http_verb, path)
            return :not_found if node.nil?

            route= node.payload
            route.params= node.params
            route
        end

        def add(route : Route)
            trail = build_node(route.verb, route.path)
            @routes.add(trail, route)

            if route.verb == :GET
                trail = build_node(:HEAD, route.path)
                @routes.add(trail, route)
            end

        rescue Radix::Tree::DuplicateError
            raise Amber::Exceptions::DuplicateRouteError.new(route)
        end

        private def build_node(http_verb : Symbol, path : String)
            "#{http_verb.to_s.downcase}#{path}"
        end
    end
end
