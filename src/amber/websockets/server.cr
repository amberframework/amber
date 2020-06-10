module Amber
  module WebSockets
    module Server
      extend self
      Log = ::Log.for(self)

      def create_endpoint(path, app_socket)
        Log.info { "Socket listening at #{path}" }
        Handler.new(path) do |socket, context|
          instance = app_socket.new(socket, context)
          socket.close && next unless instance.authorized?

          ClientSockets.add_client_socket(instance)

          socket.on_message do |message|
            instance.on_message(message)
          end

          socket.on_close do
            instance.on_disconnect
            ClientSockets.remove_client_socket(instance)
          end
        end
      end

      class Handler < HTTP::WebSocketHandler
        def initialize(@path : String, &@proc : HTTP::WebSocket, HTTP::Server::Context -> Void)
          Amber::Server.router.add_socket_route(@path, self)
        end

        def call(context)
          super
        end
      end
    end

    # Helper method to get the path of a topic
    def self.topic_path(topic)
      topic.to_s.split(":")[0..-2].join(":")
    end
  end
end
