module Amber
  module WebSockets
    abstract class ClientSocket

      property id

      enum State
        CONNECTING
        OPEN
        CLOSING
        CLOSED
      end

      abstract def on_connect
      abstract def on_message
      abstract def on_close
      
    end
  end
end