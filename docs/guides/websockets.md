# WebSockets

Amber provides a channel-based WebSocket system for real-time communication. Client sockets authenticate and subscribe to channels, where incoming and outgoing messages are routed. The system includes presence tracking, multiple message decoders, connection recovery, and error isolation between channels.

## Quick Start

Define a channel, a client socket, and wire them up in your routes:

```crystal
# src/channels/chat_channel.cr
class ChatChannel < Amber::WebSockets::Channel
  def handle_joined(client_socket, message)
    # Called when a client joins this channel
  end

  def handle_message(client_socket, message)
    # Broadcast the message to all subscribers
    rebroadcast!(message)
  end

  def handle_leave(client_socket)
    # Called when a client leaves this channel
  end
end

# src/sockets/user_socket.cr
struct UserSocket < Amber::WebSockets::ClientSocket
  channel "chat:*", ChatChannel

  def on_connect : Bool
    # Return true to allow the connection, false to reject
    true
  end
end
```

In your route configuration:

```crystal
Amber::Server.configure do
  routes :web do
    websocket "/ws", UserSocket
  end
end
```

## Channels

Channels handle the communication logic for a specific topic. Each channel class inherits from `Amber::WebSockets::Channel` and must implement `handle_message`.

### Lifecycle Callbacks

```crystal
class RoomChannel < Amber::WebSockets::Channel
  # Required: handle incoming messages
  def handle_message(client_socket, message)
    rebroadcast!(message)
  end

  # Optional: called when a client joins this channel
  def handle_joined(client_socket, message)
    # Authorization, welcome messages, etc.
  end

  # Optional: called when a client leaves this channel
  def handle_leave(client_socket)
    # Cleanup, notify others, etc.
  end

  # Optional: called after handle_joined completes
  def after_join(client_socket)
    # Post-join logic like sending welcome messages
  end

  # Optional: called after handle_leave completes
  def after_leave(client_socket)
    # Post-leave cleanup
  end

  # Optional: called when an error occurs in this channel
  def on_error(ex : Exception, client_socket)
    Log.error(exception: ex) { "Channel error: #{ex.message}" }
  end
end
```

### Broadcasting

Send messages to all subscribers of a channel topic:

```crystal
class ChatChannel < Amber::WebSockets::Channel
  def handle_message(client_socket, message)
    # Broadcast to all subscribers of this channel's topic
    rebroadcast!(message)

    # broadcast! is an alias for rebroadcast!
    broadcast!(message)
  end
end
```

### Broadcasting from Outside a Channel

Use the class-level `broadcast_to` method to send messages from controllers, background jobs, or other non-channel contexts:

```crystal
# From a controller action
class NotificationsController < ApplicationController
  def create
    ChatChannel.broadcast_to(
      "chat:lobby",
      "msg:new",
      {"message" => "Server announcement: maintenance in 5 minutes"}
    )
    respond_with { json({status: "sent"}) }
  end
end

# From a background job
class BroadcastJob < Amber::Jobs::Job
  include JSON::Serializable
  property topic : String
  property message : String

  def initialize(@topic : String, @message : String)
  end

  def perform
    ChatChannel.broadcast_to(@topic, "msg:new", {"message" => @message})
  end
end
```

## Client Sockets

A `ClientSocket` struct maps a user to a WebSocket connection. Authentication and authorization happen here, and the socket subscribes to one or more channels.

```crystal
struct UserSocket < Amber::WebSockets::ClientSocket
  channel "chat:*", ChatChannel
  channel "notifications:*", NotificationChannel

  def on_connect : Bool
    # Access session, cookies, params for authentication
    if user_id = session["user_id"]?
      true  # Allow connection
    else
      false # Reject connection (socket will be closed)
    end
  end

  def on_disconnect
    # Called when the socket disconnects
  end

  def on_reconnect
    # Called when a previously disconnected socket reconnects
    # within the reconnection window
  end

  def on_error(ex : Exception)
    # Called on socket-level errors (outside of channels)
    Log.error(exception: ex) { "Socket error: #{ex.message}" }
  end
end
```

### Channel Registration

The `channel` macro registers a channel class for a topic pattern. The `*` wildcard matches any suffix:

```crystal
struct UserSocket < Amber::WebSockets::ClientSocket
  channel "chat:*", ChatChannel           # Matches "chat:lobby", "chat:room1", etc.
  channel "notifications:*", NotifChannel # Matches "notifications:user1", etc.
end
```

### Available Context

Inside `on_connect`, you have access to:

- `session` -- The session store
- `cookies` -- The cookie store
- `params` -- Request parameters
- `context` -- The full HTTP::Server::Context

## Message Protocol

Amber WebSockets use a JSON message protocol by default. Messages have this structure:

```json
{
  "event": "join|message|leave",
  "topic": "channel:identifier",
  "payload": { ... }
}
```

### Events

| Event | Description |
|-------|-------------|
| `join` | Client subscribes to a channel topic |
| `message` | Client sends a message to a channel |
| `leave` | Client unsubscribes from a channel topic |

## Decoders

Decoders handle the serialization and deserialization of WebSocket messages. The default decoder is JSON.

### Built-in Decoders

- **JsonDecoder** (default) -- Encodes/decodes messages as JSON
- **TextDecoder** -- Passes raw text through
- **BinaryDecoder** -- Handles binary WebSocket frames

### Overriding the Decoder

```crystal
struct BinarySocket < Amber::WebSockets::ClientSocket
  channel "data:*", DataChannel

  def self.decoder : Amber::WebSockets::Decoders::Decoder
    Amber::WebSockets::Decoders::BinaryDecoder.new
  end
end
```

### Custom Decoder

```crystal
class MsgPackDecoder < Amber::WebSockets::Decoders::Decoder
  def decode(raw : String) : JSON::Any
    # Decode MessagePack to JSON::Any
  end

  def encode(payload : Hash) : String
    # Encode Hash to MessagePack string
  end

  def encode(payload : JSON::Any) : String
    # Encode JSON::Any to MessagePack string
  end

  def content_type : String
    "application/x-msgpack"
  end
end
```

## Presence Tracking

Amber automatically tracks which sockets are present in each channel topic. When a socket joins or leaves, a `presence_diff` event is broadcast to all subscribers.

### Accessing Presence Data

```crystal
class ChatChannel < Amber::WebSockets::Channel
  def handle_joined(client_socket, message)
    # Get the list of present sockets
    list = presence_list
    # => Hash(String, Hash(String, String))
    # e.g., {"socket-uuid" => {"socket_id" => "...", "joined_at" => "..."}}

    # Get the count of present sockets
    count = presence_count
    # => Int32
  end
end

# Class-level access
ChatChannel.presence_list("chat:lobby")
```

### Presence Diff Events

When a socket joins or leaves a channel, a `presence_diff` event is automatically broadcast:

```json
{
  "event": "presence_diff",
  "topic": "chat:lobby",
  "payload": {
    "joins": {
      "socket-uuid": {
        "socket_id": "...",
        "joined_at": "2024-01-15T10:30:00Z"
      }
    },
    "leaves": {}
  }
}
```

## Connection Recovery

When a client disconnects and reconnects within the reconnection window (default: 60 seconds), Amber can recover the connection:

1. The client reconnects with its `connection_id` as a query parameter
2. The server looks up any buffered messages for that connection
3. Buffered messages are sent to the client
4. The `on_reconnect` callback is invoked

```javascript
// Client-side reconnection (JavaScript)
const ws = new WebSocket(`ws://localhost:3000/ws?connection_id=${savedConnectionId}`);
```

```crystal
struct UserSocket < Amber::WebSockets::ClientSocket
  def on_reconnect
    # Restore channel state, send missed data, notify others
  end
end
```

### Configuration Constants

| Constant | Default | Description |
|----------|---------|-------------|
| `MAX_SOCKET_IDLE_TIME` | `100.seconds` | Maximum idle time before disconnect |
| `BEAT_INTERVAL` | `30.seconds` | Ping interval for keepalive |
| `RECONNECT_WINDOW` | `60.seconds` | Window for connection recovery |
| `DEFAULT_MESSAGE_BUFFER_SIZE` | `100` | Max buffered messages during disconnect |

## Error Handling

Errors in one channel are isolated and do not affect other channels or crash the socket connection. The `SubscriptionManager` catches exceptions during join, message, and leave operations and forwards them to the channel's `on_error` callback and the socket's `handle_error` method.

```crystal
class ChatChannel < Amber::WebSockets::Channel
  def handle_message(client_socket, message)
    # If this raises, only this channel is affected
    raise "Something went wrong"
  end

  def on_error(ex : Exception, client_socket)
    # Report to error tracking service
    ErrorTracker.report(ex, socket_id: client_socket.id)
  end
end

struct UserSocket < Amber::WebSockets::ClientSocket
  def handle_error(ex : Exception, context : String = "unknown")
    Log.error(exception: ex) { "Socket #{@id} error in #{context}: #{ex.message}" }
  end
end
```

## Client-Side Integration

A minimal JavaScript client for connecting to Amber WebSockets:

```javascript
const socket = new WebSocket("ws://localhost:3000/ws");

socket.onopen = () => {
  // Join a channel
  socket.send(JSON.stringify({
    event: "join",
    topic: "chat:lobby",
    payload: {}
  }));
};

socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log("Received:", message);

  if (message.event === "presence_diff") {
    // Handle presence updates
  }
};

// Send a message to a channel
function sendMessage(text) {
  socket.send(JSON.stringify({
    event: "message",
    topic: "chat:lobby",
    payload: { message: text }
  }));
}

// Leave a channel
function leaveChannel() {
  socket.send(JSON.stringify({
    event: "leave",
    topic: "chat:lobby",
    payload: {}
  }));
}
```

## Testing WebSockets

See the [Testing Guide](testing.md) for `WebSocketHelpers` and `TestWebSocket` usage.

## Source Files

- `src/amber/websockets/channel.cr` -- Abstract Channel base class with broadcasting and presence
- `src/amber/websockets/client_socket.cr` -- Abstract ClientSocket struct with authentication
- `src/amber/websockets/client_sockets.cr` -- Global socket registry
- `src/amber/websockets/subscription_manager.cr` -- Dispatches events to channels with error isolation
- `src/amber/websockets/server.cr` -- WebSocket server handler and connection recovery
- `src/amber/websockets/presence.cr` -- Module-level presence tracking store
- `src/amber/websockets/decoders/decoder.cr` -- Abstract Decoder base class
- `src/amber/websockets/decoders/json_decoder.cr` -- Default JSON decoder
- `src/amber/websockets/decoders/text_decoder.cr` -- Plain text decoder
- `src/amber/websockets/decoders/binary_decoder.cr` -- Binary frame decoder
