require "../../spec_helper"

# Connects a client to *listener*, accepts the connection with *accept_method*
# and returns whether the accepted socket has TCP_NODELAY set.
private def accepted_socket_has_tcp_nodelay?(listener : Amber::Server::TCPListener, &accept : Amber::Server::TCPListener -> TCPSocket) : Bool
  client = TCPSocket.new("127.0.0.1", listener.local_address.port)
  accepted = accept.call(listener)
  begin
    accepted.tcp_nodelay?
  ensure
    accepted.close
    client.close
  end
end

describe Amber::Server::TCPListener do
  it "sets TCP_NODELAY on each socket accept? returns, by default" do
    listener = Amber::Server::TCPListener.new("127.0.0.1", 0)
    begin
      listener.tcp_nodelay?.should be_true
      has_tcp_nodelay = accepted_socket_has_tcp_nodelay?(listener) { |server| server.accept?.should_not be_nil }
      has_tcp_nodelay.should be_true
    ensure
      listener.close
    end
  end

  it "sets TCP_NODELAY on each socket accept returns" do
    listener = Amber::Server::TCPListener.new("127.0.0.1", 0)
    begin
      has_tcp_nodelay = accepted_socket_has_tcp_nodelay?(listener) { |server| server.accept.as(TCPSocket) }
      has_tcp_nodelay.should be_true
    ensure
      listener.close
    end
  end

  it "leaves Nagle on when tcp_nodelay is off" do
    listener = Amber::Server::TCPListener.new("127.0.0.1", 0)
    listener.tcp_nodelay = false
    begin
      has_tcp_nodelay = accepted_socket_has_tcp_nodelay?(listener) { |server| server.accept?.should_not be_nil }
      has_tcp_nodelay.should be_false
    ensure
      listener.close
    end
  end

  it "returns nil from accept? once closed" do
    listener = Amber::Server::TCPListener.new("127.0.0.1", 0)
    listener.close
    listener.accept?.should be_nil
  end
end

describe Amber::Server do
  describe ".bind_tcp_listener" do
    it "serves HTTP on a TCPListener and returns the address it listens on" do
      server = HTTP::Server.new { |context| context.response.print "over the listener" }
      address = Amber::Server.bind_tcp_listener(server, "127.0.0.1", 0, false, true)
      address.port.should be > 0
      spawn { server.listen }
      begin
        response = HTTP::Client.get("http://127.0.0.1:#{address.port}/")
        response.body.should eq "over the listener"
      ensure
        server.close
      end
    end
  end
end
