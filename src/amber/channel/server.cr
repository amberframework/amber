module Amber
  module WebSockets
    module Server


      class Handler < HTTP::WebSocketHandler
        def initialize(@path : String, &@proc : HTTP::WebSocket, HTTP::Server::Context -> Void)
          route = Route.new(path, self)
          Router.instance.add(route)
        end

        def call(context)
          puts "socket call"
          super
        end
      end
    end
  end
end