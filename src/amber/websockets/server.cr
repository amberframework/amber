module Amber
  module WebSockets
    module Server
      extend self

      def create_endpoint(path, app_socket)
        spawn do
          Amber::Server.instance.log.info "socket listening at #{path}"
          Handler.new(path) do |socket|
            instance = app_socket.new(socket)
            socket.close && next unless instance.authorized?
            
            ClientSockets.add_client_socket(instance)

            socket.on_message do |message|
              
            end

            socket.on_close do
              ClientSockets.remove_client_socket(instance)
            end
          end
        end

        ClientSockets.setup_heartbeat
      end

      class Handler < HTTP::WebSocketHandler
        def initialize(@path : String, &@proc : HTTP::WebSocket, HTTP::Server::Context -> Void)
          # route = Route.new(path, self)
          # Pipe::Router.instance.add(route)
        end

        def call(context)
          puts "socket call"
          super
        end
      end
    end
  end
end