module Amber
  module WebSockets
    module Server
      extend self
      Log = ::Log.for(self)

      def create_endpoint(path, app_socket)
        Log.info { "Socket listening at #{path}" }
        Handler.new(path) do |socket, context|
          # Check for a reconnection attempt via query parameter
          reconnection_id = context.request.query_params["connection_id"]?
          recovered = nil

          if reconnection_id
            recovered = ClientSockets.recover_connection(reconnection_id)
          end

          if recovered && reconnection_id
            instance = app_socket.new(socket, context, reconnection_id.not_nil!)
          else
            instance = app_socket.new(socket, context)
          end

          socket.close && next unless instance.authorized?

          ClientSockets.add_client_socket(instance)

          # If this is a reconnection, flush buffered messages and invoke callback
          if recovered
            recovered.list_of_buffered_messages.each do |buffered_msg|
              begin
                socket.send(buffered_msg)
              rescue ex : IO::Error
                Log.error(exception: ex) { "Failed to send buffered message during reconnection" }
              end
            end
            instance.on_reconnect
          end

          socket.on_message do |message|
            instance.on_message(message)
          end

          socket.on_close do
            instance.on_disconnect
            ClientSockets.track_disconnection(instance)
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
