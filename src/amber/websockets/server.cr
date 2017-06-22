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
              instance.on_message(message)
            end

            socket.on_close do
              ClientSockets.remove_client_socket(instance)
            end
          end

          ClientSockets.setup_heartbeat
        end
      end

      class Handler < HTTP::WebSocketHandler
        def initialize(@path : String, &@proc : HTTP::WebSocket, HTTP::Server::Context -> Void)
          Router::Router.instance.add_socket_route(@path, self)
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
