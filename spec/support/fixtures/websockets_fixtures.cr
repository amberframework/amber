struct UserSocket < Amber::WebSockets::ClientSocket
  property test_field = Array(String).new

  channel "user_room:*", UserChannel
  channel "secondary_room:*", SecondaryChannel

  def on_disconnect(**args)
    test_field.push("on close #{self.id}")
  end
end

class UserChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new

  def handle_leave(client_socket)
    test_field.push("handle leave #{client_socket.id}")
  end

  def handle_joined(client_socket, msg)
    test_field.push("handle joined #{client_socket.id}")
  end

  def handle_message(client_socket, msg)
    test_field.push(msg["payload"]["message"].as_s)
  end
end

class SecondaryChannel < Amber::WebSockets::Channel
  property test_field = Array(String).new

  def handle_leave(client_socket)
    test_field.push("secondary channel handle leave #{client_socket.id}")
  end

  def handle_joined(client_socket, msg)
    test_field.push("secondary channel handle joined #{client_socket.id}")
  end

  def handle_message(client_socket, msg)
    test_field.push("secondary channel #{msg["payload"]["message"].as_s}")
  end
end
