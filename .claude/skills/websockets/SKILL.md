---
name: amber-websockets
description: Amber V2 WebSocket system — channels, client sockets, presence tracking, message decoders, broadcasting, connection recovery
user-invocable: false
---

# Amber V2 WebSocket System

Amber provides a channel-based WebSocket system for real-time communication. Client sockets authenticate connections, channels handle topic-based message routing, and the PubSub adapter pattern enables pluggable messaging backends.

## Architecture Overview

The WebSocket system has four layers:

1. **ClientSocket** -- authenticates the connection, maps to an HTTP::WebSocket, registers channel subscriptions
2. **Channel** -- handles messages for a specific topic, manages presence, broadcasts to subscribers
3. **SubscriptionManager** -- dispatches join/message/leave events to the correct channel instance per socket
4. **PubSub Adapter** -- routes messages between channel instances (in-memory default, Redis optional)

Message flow: Client sends JSON over WebSocket -> ClientSocket decodes it -> SubscriptionManager dispatches by event type -> Channel processes the message.

## 1. Defining a Channel

Channels are abstract classes. You must implement `handle_message`. All other callbacks are optional.

```crystal
class ChatChannel < Amber::WebSockets::Channel
  # Required: process incoming messages from subscribed clients
  def handle_message(client_socket, msg)
    # msg is JSON::Any with keys: "event", "topic", "subject", "payload"
    rebroadcast!(msg)
  end

  # Optional: called when a client joins this channel
  def handle_joined(client_socket, message)
    # Authorization or setup logic
  end

  # Optional: called when a client leaves this channel
  def handle_leave(client_socket)
    # Cleanup logic
  end

  # Optional: called after handle_joined completes successfully
  def after_join(client_socket)
    # Post-join logic like sending a welcome message
  end

  # Optional: called after handle_leave completes successfully
  def after_leave(client_socket)
    # Post-leave cleanup
  end

  # Optional: called when an error occurs in any channel callback
  # Default implementation logs the error.
  def on_error(ex : Exception, client_socket)
    Log.error(exception: ex) { "Channel error: #{ex.message}" }
  end
end
```

### Channel Callback Order

On subscribe: `handle_joined` -> `track_presence` -> `after_join`
On unsubscribe: `handle_leave` -> `untrack_presence` -> `after_leave`

If any callback raises, `on_error` is called and the exception does not propagate to the socket or crash other channels.

### Sending Messages from a Channel

Inside a channel instance:

```crystal
def handle_message(client_socket, msg)
  # Send to all subscribers of this channel topic (including sender)
  rebroadcast!(msg)

  # Equivalent to rebroadcast!
  broadcast!(msg)

  # Send to a specific topic (different from this channel's topic)
  rebroadcast!(msg, topic: "other_room:456")
end
```

`rebroadcast!` accepts a `Hash` or any object. Hash messages are sent directly. Other types are wrapped in `{"event" => "message", "topic" => topic, "payload" => message}`.

## 2. Defining a ClientSocket

ClientSockets are abstract structs that map a user to a WebSocket connection. They register which channels are available and handle authentication.

```crystal
struct UserSocket < Amber::WebSockets::ClientSocket
  # Register channels with topic patterns. The "*" is a wildcard for the topic suffix.
  channel "chat_room:*", ChatChannel
  channel "notifications:*", NotificationChannel

  # Optional: authenticate the connection. Return false to reject.
  # Default returns true (all connections accepted).
  def on_connect : Bool
    # Access session, cookies, params for auth
    return true if session["user_id"]?
    false
  end

  # Optional: called when the socket disconnects
  def on_disconnect
  end

  # Optional: called when a previously disconnected socket reconnects
  # within the reconnection window
  def on_reconnect
  end

  # Optional: called on socket-level errors (outside channel scope)
  def on_error(ex : Exception)
    Log.error(exception: ex) { "Socket error: #{ex.message}" }
  end

  # Optional: error reporting hook for external services
  def handle_error(ex : Exception, context : String = "unknown")
    Log.error(exception: ex) { "Socket #{@id} error in #{context}: #{ex.message}" }
  end
end
```

### ClientSocket Properties

Inside a ClientSocket, you have access to:

- `id : String` -- unique socket ID (UUID), changes on each connection
- `connection_id : String` -- stable ID that persists across reconnections
- `socket : HTTP::WebSocket` -- the underlying WebSocket
- `session` -- the session store from the HTTP context
- `cookies` -- the cookie store from the HTTP context
- `raw_params : Amber::Router::Params` -- raw request parameters
- `params` -- validated request parameters (wraps raw_params with validation support)
- `channels : Hash(String, Channel)` -- channel instances for this socket

### Selecting a Decoder

The default decoder is `JsonDecoder`. Override `self.decoder` to change it:

```crystal
struct BinarySocket < Amber::WebSockets::ClientSocket
  channel "data_stream:*", DataChannel

  def self.decoder : Amber::WebSockets::Decoders::Decoder
    Amber::WebSockets::Decoders::BinaryDecoder.new
  end
end
```

## 3. Message Handling and Decoders

All messages flow through a decoder before dispatch. The decoder converts raw WebSocket data into `JSON::Any` with a standard structure.

### Message Structure

The standard message format expected by the dispatch system:

```json
{
  "event": "join" | "message" | "leave",
  "topic": "chat_room:123",
  "subject": "msg:new",
  "payload": { "message": "hello" }
}
```

The `event` field determines how the SubscriptionManager routes the message:
- `"join"` -- subscribes the socket to the channel for that topic
- `"message"` -- dispatches to the channel's `handle_message`
- `"leave"` -- unsubscribes the socket from the channel

### Built-in Decoders

**JsonDecoder** (default) -- parses raw JSON strings directly. Raises `DecoderError` on invalid JSON.

```crystal
decoder = Amber::WebSockets::Decoders::JsonDecoder.new
decoded = decoder.decode(%|{"event":"message","topic":"room:1"}|)
decoded["event"].as_s  # => "message"
```

**TextDecoder** -- wraps plain text in a standard message structure. If the text is valid JSON, it parses it as JSON instead.

```crystal
decoder = Amber::WebSockets::Decoders::TextDecoder.new
decoded = decoder.decode("hello world")
decoded["event"].as_s    # => "message"
decoded["payload"].as_s  # => "hello world"
```

**BinaryDecoder** -- uses a length-prefixed binary format encoded as Base64. Each field is stored as `[key_length:4 bytes][key_data][value_length:4 bytes][value_data]` with a field count header.

```crystal
decoder = Amber::WebSockets::Decoders::BinaryDecoder.new
encoded = decoder.encode({"event" => "message", "topic" => "room:1"})
decoded = decoder.decode(encoded)
decoded["event"].as_s  # => "message"
```

### Custom Decoders

Inherit from `Amber::WebSockets::Decoders::Decoder` and implement all abstract methods:

```crystal
class MsgPackDecoder < Amber::WebSockets::Decoders::Decoder
  def decode(raw : String) : JSON::Any
    # Custom decoding logic
    # Raise DecoderError on failure
  end

  def encode(payload : Hash) : String
    # Serialize to string
  end

  def encode(payload : JSON::Any) : String
    # Serialize to string
  end

  def content_type : String
    "application/x-msgpack"
  end
end
```

When decoding fails, a `Decoders::DecoderError` is raised. The error includes the `raw_message` for debugging. The socket's `on_error` and `handle_error` methods are both called.

## 4. Presence Tracking

Presence is tracked automatically when sockets subscribe to and unsubscribe from channels. The `Amber::WebSockets::Presence` module stores presence data in a thread-safe, module-level store shared across all channel classes.

### Querying Presence (Instance Level)

Inside a channel instance:

```crystal
class ChatChannel < Amber::WebSockets::Channel
  def handle_joined(client_socket, message)
    # Get all present sockets in this channel topic
    list = presence_list
    # => {"socket-uuid-1" => {"socket_id" => "socket-uuid-1", "joined_at" => "2026-01-15T10:30:00Z"}, ...}

    # Get the count
    count = presence_count
    # => 5
  end

  def handle_message(client_socket, msg)
    rebroadcast!(msg)
  end
end
```

### Querying Presence (Class Level)

From outside a channel instance (controllers, jobs, etc.):

```crystal
# Get presence data for a specific topic
presence = ChatChannel.presence_list("chat_room:lobby")

# Reset all presence data (useful in tests)
Amber::WebSockets::Channel.reset_presence

# Direct module access
Amber::WebSockets::Presence.list("chat_room:lobby")
Amber::WebSockets::Presence.count("chat_room:lobby")
Amber::WebSockets::Presence.has_socket?("chat_room:lobby", socket_id)
```

### Presence Diff Events

When a socket joins or leaves a channel, a `presence_diff` event is automatically broadcast to all subscribers of that topic:

```json
{
  "event": "presence_diff",
  "topic": "chat_room:lobby",
  "payload": {
    "joins": {
      "socket-uuid-1": {
        "socket_id": "socket-uuid-1",
        "joined_at": "2026-01-15T10:30:00Z"
      }
    },
    "leaves": {}
  }
}
```

Presence metadata always includes `socket_id` and `joined_at`. The metadata is set internally during `track_presence`.

## 5. Broadcasting

### From Inside a Channel

```crystal
class ChatChannel < Amber::WebSockets::Channel
  def handle_message(client_socket, msg)
    # Rebroadcast to all subscribers of this channel's topic
    rebroadcast!(msg)
  end
end
```

### From Outside a Channel (Controllers, Jobs, etc.)

**Class-level broadcast on Channel:**

```crystal
# Broadcast to all subscribers of a specific topic
ChatChannel.broadcast_to("chat_room:lobby", "msg:new", {"message" => "Server announcement"})
```

This sends a JSON message directly to each subscriber's WebSocket:

```json
{
  "event": "msg:new",
  "topic": "chat_room:lobby",
  "payload": {"message": "Server announcement"}
}
```

**Class-level broadcast on ClientSocket:**

```crystal
UserSocket.broadcast("message", "chat_room:lobby", "msg:new", {"message" => "hello"})
```

This routes through the channel's `rebroadcast!` method and sends:

```json
{
  "event": "message",
  "topic": "chat_room:lobby",
  "subject": "msg:new",
  "payload": {"message": "hello"}
}
```

### Error Handling During Broadcast

`Channel.broadcast_to` catches `IO::Error` per socket so a closed socket does not prevent delivery to other subscribers.

## 6. Connection Recovery

Amber supports automatic reconnection with message buffering.

### How It Works

1. When a socket disconnects, `ClientSockets.track_disconnection` stores the `connection_id`, disconnect time, and subscribed topics
2. Messages sent to the disconnected socket during the window are buffered (up to `DEFAULT_MESSAGE_BUFFER_SIZE` = 100 messages)
3. When a client reconnects with `?connection_id=<id>` in the query string, the server recovers the connection
4. All buffered messages are flushed to the reconnected socket
5. The `on_reconnect` callback fires on the ClientSocket
6. After the reconnection window expires (default 60 seconds), the disconnected state is cleaned up

### Client-Side Reconnection

The client must include the `connection_id` as a query parameter when reconnecting:

```javascript
// Initial connection
const ws = new WebSocket("ws://localhost:3000/ws?token=abc");

// Store the connection_id received from server
let connectionId = null;

// On reconnection attempt
ws.onclose = function() {
  setTimeout(() => {
    const url = connectionId
      ? `ws://localhost:3000/ws?token=abc&connection_id=${connectionId}`
      : "ws://localhost:3000/ws?token=abc";
    const newWs = new WebSocket(url);
  }, 1000);
};
```

### Server-Side Reconnection Hook

```crystal
struct UserSocket < Amber::WebSockets::ClientSocket
  channel "chat_room:*", ChatChannel

  def on_reconnect
    # Restore state, notify other users, etc.
    # self.connection_id contains the stable identifier
  end
end
```

### Configuration

```crystal
# Set the reconnection window (default: 60 seconds)
Amber::WebSockets::ClientSockets.reconnect_window = 120.seconds

# Set the message buffer size (default: 100)
Amber::WebSockets::ClientSockets.max_message_buffer_size = 200

# Clear all disconnected connection state (useful in tests)
Amber::WebSockets::ClientSockets.clear_disconnected_connections
```

### Constants

Defined on `ClientSocket`:

- `MAX_SOCKET_IDLE_TIME` = 100 seconds (disconnect if no pong received within this window)
- `BEAT_INTERVAL` = 30 seconds (ping interval)
- `RECONNECT_WINDOW` = 60 seconds (how long a disconnected socket can reconnect)
- `DEFAULT_MESSAGE_BUFFER_SIZE` = 100 (max buffered messages per disconnected connection)

## 7. WebSocket Routes

Register WebSocket endpoints inside a `routes` block using the `websocket` method:

```crystal
Amber::Server.configure do
  routes :web do
    # HTTP routes...
    get "/", HomeController, :index
  end

  routes :api do
    # API routes...
  end

  # WebSocket endpoints are registered in any routes block
  routes :web do
    websocket "/ws", UserSocket
    websocket "/admin/ws", AdminSocket
  end
end
```

The `websocket` method calls `Amber::WebSockets::Server.create_endpoint(path, app_socket)`, which creates an `HTTP::WebSocketHandler` and registers it with the router.

The WebSocket handler:
1. Checks for a `connection_id` query parameter for reconnection
2. Creates a new ClientSocket instance (or reconnects an existing one)
3. Calls `on_connect` -- closes the socket if it returns false
4. Adds the socket to the global `ClientSockets` collection
5. Flushes buffered messages if reconnecting
6. Wires up `on_message` and `on_close` handlers

## 8. PubSub Adapter Integration

Channels use a PubSub adapter for inter-process message routing. The adapter pattern allows swapping between in-memory (development) and distributed (production) backends.

### Adapter Selection

Channels check for adapters in this order:
1. `Amber::Server.instance.adapter_based_pubsub` (new adapter system via `Amber::Adapters::PubSubAdapter`)
2. `Amber::Server.pubsub_adapter` (legacy `WebSockets::Adapters::MemoryAdapter`)

### Built-in Adapters

**MemoryPubSubAdapter** (default) -- in-memory, single-instance only:

```crystal
Amber::Server.configure do
  adapter_based_pubsub = Amber::Adapters::MemoryPubSubAdapter.new
end
```

The `PubSubAdapter` abstract class defines the interface:

```crystal
abstract class PubSubAdapter
  abstract def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
  abstract def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
  abstract def unsubscribe(topic : String) : Nil
  abstract def unsubscribe_all : Nil
  abstract def close : Nil

  # Optional overrides with defaults:
  def healthy? : Bool           # => true
  def subscriber_count : Int32  # => 0
  def active_topics : Array(String)  # => []
  protected def on_topic_activated(topic : String) : Nil
  protected def on_topic_deactivated(topic : String) : Nil
end
```

### Writing a Custom Adapter

For production multi-instance deployments, implement your own adapter:

```crystal
class RedisPubSubAdapter < Amber::Adapters::PubSubAdapter
  def initialize(@redis : Redis::Client)
  end

  def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
    @redis.publish(topic, {sender_id: sender_id, message: message}.to_json)
  end

  def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
    # Set up Redis subscription with callback
  end

  def unsubscribe(topic : String) : Nil
    @redis.unsubscribe(topic)
  end

  def unsubscribe_all : Nil
    # Unsubscribe from all topics
  end

  def close : Nil
    @redis.close
  end
end
```

## 9. Client-Side JavaScript Integration

Amber's WebSocket protocol uses a simple JSON message format. The client must send properly structured messages for the dispatch system to work.

### Basic JavaScript Client

```javascript
class AmberSocket {
  constructor(url) {
    this.url = url;
    this.ws = new WebSocket(url);
    this.connectionId = null;
    this.channels = {};

    this.ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      this.handleMessage(msg);
    };

    this.ws.onclose = () => {
      this.scheduleReconnect();
    };
  }

  // Join a channel topic
  join(topic) {
    this.send({ event: "join", topic: topic, payload: {} });
    this.channels[topic] = true;
  }

  // Leave a channel topic
  leave(topic) {
    this.send({ event: "leave", topic: topic, payload: {} });
    delete this.channels[topic];
  }

  // Send a message to a channel topic
  sendMessage(topic, subject, payload) {
    this.send({
      event: "message",
      topic: topic,
      subject: subject,
      payload: payload
    });
  }

  handleMessage(msg) {
    if (msg.event === "presence_diff") {
      // Handle presence changes
      console.log("Joins:", msg.payload.joins);
      console.log("Leaves:", msg.payload.leaves);
      return;
    }
    // Handle regular messages
    console.log(`[${msg.topic}] ${msg.event}:`, msg.payload);
  }

  send(data) {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  scheduleReconnect() {
    setTimeout(() => {
      const reconnectUrl = this.connectionId
        ? `${this.url}?connection_id=${this.connectionId}`
        : this.url;
      this.ws = new WebSocket(reconnectUrl);
    }, 1000);
  }
}

// Usage
const socket = new AmberSocket("ws://localhost:3000/ws");
socket.ws.onopen = () => {
  socket.join("chat_room:lobby");
  socket.sendMessage("chat_room:lobby", "msg:new", { message: "Hello!" });
};
```

### Event Types the Server Sends

| Event | Description |
|-------|-------------|
| `presence_diff` | A socket joined or left the channel. Payload has `joins` and `leaves` hashes. |
| `msg:new` (or custom) | Application-defined events from `rebroadcast!` or `broadcast_to`. |
| `message` | Generic message event from non-Hash rebroadcast. |

## 10. Key Source Files

| File | Purpose |
|------|---------|
| `src/amber/websockets/channel.cr` | Abstract Channel class with message handling, broadcasting, presence integration |
| `src/amber/websockets/client_socket.cr` | Abstract ClientSocket struct with auth, decoder selection, heartbeat, reconnection |
| `src/amber/websockets/client_sockets.cr` | Global ClientSocket registry, heartbeat spawning, disconnection tracking, message buffering |
| `src/amber/websockets/server.cr` | WebSocket endpoint creation, HTTP upgrade handling, reconnection recovery |
| `src/amber/websockets/subscription_manager.cr` | Dispatches join/message/leave events to channel instances with error isolation |
| `src/amber/websockets/presence.cr` | Thread-safe module-level presence store shared across all channel classes |
| `src/amber/websockets/decoders/decoder.cr` | Abstract Decoder base class and DecoderError |
| `src/amber/websockets/decoders/json_decoder.cr` | Default JSON decoder |
| `src/amber/websockets/decoders/text_decoder.cr` | Plain text decoder with JSON fallback |
| `src/amber/websockets/decoders/binary_decoder.cr` | Length-prefixed binary decoder (Base64 transport) |
| `src/amber/websockets/adapters/memory.cr` | Legacy in-memory PubSub adapter for WebSocket channels |
| `src/amber/adapters/pubsub_adapter.cr` | Abstract PubSubAdapter base class (new adapter system) |
| `src/amber/adapters/memory_pubsub_adapter.cr` | In-memory PubSubAdapter implementation (new adapter system) |
| `src/amber/dsl/router.cr` | Router DSL with `websocket` method for endpoint registration |
| `src/amber/server/server.cr` | Server configuration including PubSub adapter assignment |
