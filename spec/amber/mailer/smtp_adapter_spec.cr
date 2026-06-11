require "../../spec_helper"

# A mock SMTP server that runs on a local TCP port and records commands.
# Used to verify the SMTP protocol implementation without connecting
# to an actual mail server.
class MockSMTPServer
  getter list_of_received_commands : Array(String) = [] of String
  getter received_data : String = ""
  property is_running : Bool = false

  @server : TCPServer?
  @auth_required : Bool
  @port : Int32

  def initialize(@port : Int32, @auth_required : Bool = false)
  end

  def port : Int32
    @port
  end

  def start : Nil
    @is_running = true
    @server = TCPServer.new("127.0.0.1", @port)

    spawn do
      begin
        while @is_running
          if server = @server
            if client = server.accept?
              handle_client(client)
            end
          end
        end
      rescue ex : IO::Error
        # Server was closed
      end
    end

    # Give the server a moment to start
    sleep(50.milliseconds)
  end

  def stop : Nil
    @is_running = false
    @server.try(&.close)
  end

  private def handle_client(client : TCPSocket) : Nil
    # Send greeting
    client.puts "220 mock.smtp.server ESMTP ready"

    in_data_mode = false

    while line = client.gets
      line = line.strip

      if in_data_mode
        if line == "."
          in_data_mode = false
          client.puts "250 OK message queued"
        else
          @received_data += line + "\n"
        end
        next
      end

      @list_of_received_commands << line

      case
      when line.starts_with?("EHLO")
        if @auth_required
          client.puts "250-mock.smtp.server Hello"
          client.puts "250-AUTH LOGIN PLAIN"
          client.puts "250 OK"
        else
          client.puts "250-mock.smtp.server Hello"
          client.puts "250 OK"
        end
      when line.starts_with?("AUTH LOGIN")
        client.puts "334 VXNlcm5hbWU6" # "Username:" in base64
      when line == Base64.strict_encode("testuser")
        client.puts "334 UGFzc3dvcmQ6" # "Password:" in base64
      when line == Base64.strict_encode("testpass")
        client.puts "235 Authentication successful"
      when line.starts_with?("MAIL FROM:")
        client.puts "250 OK"
      when line.starts_with?("RCPT TO:")
        client.puts "250 OK"
      when line == "DATA"
        in_data_mode = true
        client.puts "354 Start mail input"
      when line == "QUIT"
        client.puts "221 Bye"
        client.close
        break
      else
        client.puts "500 Unrecognized command"
      end
    end
  rescue ex : IO::Error
    # Client disconnected
  end
end

describe Amber::Mailer::SMTPAdapter do
  describe "#initialize" do
    it "creates an adapter with default values" do
      adapter = Amber::Mailer::SMTPAdapter.new
      adapter.host.should eq("localhost")
      adapter.port.should eq(25)
      adapter.username.should be_nil
      adapter.password.should be_nil
      adapter.use_tls.should be_false
      adapter.helo_domain.should eq("localhost")
    end

    it "creates an adapter with custom values" do
      adapter = Amber::Mailer::SMTPAdapter.new(
        host: "smtp.example.com",
        port: 587,
        username: "user",
        password: "pass",
        use_tls: false,
        helo_domain: "myapp.com",
      )

      adapter.host.should eq("smtp.example.com")
      adapter.port.should eq(587)
      adapter.username.should eq("user")
      adapter.password.should eq("pass")
      adapter.use_tls.should be_false
      adapter.helo_domain.should eq("myapp.com")
    end
  end

  describe "#deliver" do
    it "sends an email via SMTP protocol" do
      port = 30025
      server = MockSMTPServer.new(port)
      server.start

      begin
        adapter = Amber::Mailer::SMTPAdapter.new(
          host: "127.0.0.1",
          port: port,
          use_tls: false,
          helo_domain: "test.local",
        )

        email = Amber::Mailer::Email.new(
          to: ["alice@example.com"],
          from: "sender@example.com",
          subject: "Test Email",
          text_body: "Hello, World!",
        )

        result = adapter.deliver(email)
        result.is_successful.should be_true

        # Verify SMTP commands were sent
        commands = server.list_of_received_commands
        commands.any?(&.starts_with?("EHLO test.local")).should be_true
        commands.any?(&.starts_with?("MAIL FROM:<sender@example.com>")).should be_true
        commands.any?(&.starts_with?("RCPT TO:<alice@example.com>")).should be_true
        commands.should contain("DATA")
        commands.should contain("QUIT")
      ensure
        server.stop
      end
    end

    it "sends RCPT TO for all recipients including cc and bcc" do
      port = 30026
      server = MockSMTPServer.new(port)
      server.start

      begin
        adapter = Amber::Mailer::SMTPAdapter.new(
          host: "127.0.0.1",
          port: port,
          use_tls: false,
        )

        email = Amber::Mailer::Email.new(
          to: ["to@example.com"],
          from: "sender@example.com",
          cc: ["cc@example.com"],
          bcc: ["bcc@example.com"],
          text_body: "Test",
        )

        result = adapter.deliver(email)
        result.is_successful.should be_true

        commands = server.list_of_received_commands
        commands.any?(&.starts_with?("RCPT TO:<to@example.com>")).should be_true
        commands.any?(&.starts_with?("RCPT TO:<cc@example.com>")).should be_true
        commands.any?(&.starts_with?("RCPT TO:<bcc@example.com>")).should be_true
      ensure
        server.stop
      end
    end

    it "authenticates with AUTH LOGIN when credentials are provided" do
      port = 30027
      server = MockSMTPServer.new(port, auth_required: true)
      server.start

      begin
        adapter = Amber::Mailer::SMTPAdapter.new(
          host: "127.0.0.1",
          port: port,
          username: "testuser",
          password: "testpass",
          use_tls: false,
        )

        email = Amber::Mailer::Email.new(
          to: ["alice@example.com"],
          from: "sender@example.com",
          text_body: "Auth test",
        )

        result = adapter.deliver(email)
        result.is_successful.should be_true

        commands = server.list_of_received_commands
        commands.should contain("AUTH LOGIN")
        commands.should contain(Base64.strict_encode("testuser"))
        commands.should contain(Base64.strict_encode("testpass"))
      ensure
        server.stop
      end
    end

    it "sends the MIME message as DATA content" do
      port = 30028
      server = MockSMTPServer.new(port)
      server.start

      begin
        adapter = Amber::Mailer::SMTPAdapter.new(
          host: "127.0.0.1",
          port: port,
          use_tls: false,
        )

        email = Amber::Mailer::Email.new(
          to: ["alice@example.com"],
          from: "sender@example.com",
          subject: "Data Test",
          text_body: "Hello from SMTP",
        )

        adapter.deliver(email)

        data = server.received_data
        data.should contain("From: sender@example.com")
        data.should contain("Subject: Data Test")
        data.should contain("Hello from SMTP")
      ensure
        server.stop
      end
    end

    it "returns a failure result when connection is refused" do
      adapter = Amber::Mailer::SMTPAdapter.new(
        host: "127.0.0.1",
        port: 39999,
        use_tls: false,
      )

      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "b@example.com",
        text_body: "Fail",
      )

      result = adapter.deliver(email)
      result.is_successful.should be_false
      result.error.should_not be_nil
    end
  end
end
