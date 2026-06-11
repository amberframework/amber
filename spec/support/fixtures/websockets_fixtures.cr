struct UserSocket < Amber::WebSockets::ClientSocket
  property test_field = Array(String).new
  property list_of_errors = Array(Exception).new

  channel "user_room:*", UserChannel

  def on_disconnect(**args)
    test_field.push("on close #{self.id}")
  end

  def on_reconnect
    test_field.push("reconnected #{self.connection_id}")
  end

  def on_error(ex : Exception)
    list_of_errors.push(ex)
  end

  def handle_error(ex : Exception, context : String = "unknown")
    list_of_errors.push(ex)
  end
end

# A socket type that uses the text decoder
struct TextDecoderSocket < Amber::WebSockets::ClientSocket
  channel "text_room:*", TextChannel

  def self.decoder : Amber::WebSockets::Decoders::Decoder
    Amber::WebSockets::Decoders::TextDecoder.new
  end
end

class UserChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new
  property list_of_errors = Array(Exception).new

  def handle_leave(client_socket)
    test_field.push("handle leave #{client_socket.id}")
  end

  def handle_joined(client_socket, msg)
    test_field.push("handle joined #{client_socket.id}")
  end

  def after_join(client_socket)
    test_field.push("after join #{client_socket.id}")
  end

  def after_leave(client_socket)
    test_field.push("after leave #{client_socket.id}")
  end

  def on_error(ex : Exception, client_socket)
    list_of_errors.push(ex)
  end

  def handle_message(client_socket, msg)
    test_field.push(msg["payload"]["message"].as_s)
  end
end

class TextChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new

  def handle_joined(client_socket, msg)
    test_field.push("handle joined #{client_socket.id}")
  end

  def handle_leave(client_socket)
    test_field.push("handle leave #{client_socket.id}")
  end

  def handle_message(client_socket, msg)
    test_field.push(msg["payload"]?.try(&.as_s) || "no payload")
  end
end

# A channel that raises errors to test error isolation
class ErrorChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new
  property list_of_errors = Array(Exception).new

  def handle_joined(client_socket, msg)
    raise "join error"
  end

  def handle_message(client_socket, msg)
    raise "message error"
  end

  def on_error(ex : Exception, client_socket)
    list_of_errors.push(ex)
  end
end
