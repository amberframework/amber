require "radix"

module Amber
    class Router
        INSTANCE = new

        def initialize
            @routes = Radix::Tree(Symbol).new
        end

        def call(context)
            process(context)
        end

        private def process(context : HTTP::Server::Context)
        cd
        end

        # This registers all the routes for the application
        def draw(&block) : Nil
            with self yield
        end

        def add(http_verb, path, action)
            @routes.add "/#{http_verb.downcase}#{path}", action
        end

        def match(method, path)
            @routes.find "/#{http_verb.downcase}#{path}"
        end
    end
end
