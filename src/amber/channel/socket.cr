module Amber
  module WebSockets
    class ClientSocket

      property id

      enum State
        CONNECTING
        OPEN
        CLOSING
        CLOSED
      end
      
    end
  end
end