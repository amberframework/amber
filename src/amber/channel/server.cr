module Amber
  module WebSockets
    module Server
      @@context = uninitialized HTTP::Server::Context

      def set_context(ctx)
        @@context = ctx
        ws = HTTP::WebSocketHandler.new "/"
        puts ws
      end

    end
  end
end