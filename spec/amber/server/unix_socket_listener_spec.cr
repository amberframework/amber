require "../../spec_helper"

# Binds a socket file at *socket_path* and closes it without listening or
# deleting the file, as a server that stopped without cleaning up leaves it.
private def leave_stale_socket(socket_path : String) : Nil
  socket = Socket.unix(Socket::Type::STREAM)
  socket.bind(Socket::UNIXAddress.new(socket_path))
  socket.close
end

# Runs the block with `server.unix_socket`, the process count and the TLS
# files set as given, and puts the previous values back afterward.
private def with_listener_settings(unix_socket : String?, process_count : Int32 = 1, ssl_files : String? = nil, &)
  settings = Amber.settings
  original_unix_socket = settings.server.unix_socket
  original_process_count = settings.process_count
  original_key_file = settings.ssl_key_file
  original_cert_file = settings.ssl_cert_file
  begin
    settings.server.unix_socket = unix_socket
    settings.process_count = process_count
    settings.ssl_key_file = ssl_files
    settings.ssl_cert_file = ssl_files
    yield
  ensure
    settings.server.unix_socket = original_unix_socket
    settings.process_count = original_process_count
    settings.ssl_key_file = original_key_file
    settings.ssl_cert_file = original_cert_file
  end
end

describe Amber::Server do
  describe ".remove_stale_unix_socket" do
    it "removes a socket file that no server accepts connections on" do
      socket_path = File.tempname("amber-stale", ".sock")
      begin
        leave_stale_socket(socket_path)
        File.info(socket_path, follow_symlinks: false).type.socket?.should be_true

        Amber::Server.remove_stale_unix_socket(socket_path)

        File.exists?(socket_path).should be_false
      ensure
        File.delete?(socket_path)
      end
    end

    it "refuses to take over a socket another server still listens on" do
      socket_path = File.tempname("amber-active", ".sock")
      running_server = UNIXServer.new(socket_path)
      begin
        expect_raises(Socket::BindError, /in use by another running server/) do
          Amber::Server.remove_stale_unix_socket(socket_path)
        end

        File.exists?(socket_path).should be_true
        client = UNIXSocket.new(socket_path)
        client.close
      ensure
        running_server.close
        File.delete?(socket_path)
      end
    end

    it "leaves a file that is not a socket for the bind to report" do
      file_path = File.tempname("amber-not-a-socket", ".sock")
      File.write(file_path, "keep me")
      begin
        Amber::Server.remove_stale_unix_socket(file_path)
        File.read(file_path).should eq "keep me"
      ensure
        File.delete?(file_path)
      end
    end
  end

  describe ".bind_unix_socket" do
    it "binds over a stale socket while holding the path's lock file" do
      socket_path = File.tempname("amber-bind", ".sock")
      server = HTTP::Server.new { |context| context.response.print "ok" }
      begin
        leave_stale_socket(socket_path)
        Amber::Server.bind_unix_socket(server, socket_path)

        File.exists?("#{socket_path}.lock").should be_true
        File.info(socket_path, follow_symlinks: false).type.socket?.should be_true
      ensure
        server.close
        File.delete?(socket_path)
        File.delete?("#{socket_path}.lock")
      end
    end

    it "refuses a path another server is bound to and leaves that server running" do
      socket_path = File.tempname("amber-bind-busy", ".sock")
      first_server = HTTP::Server.new { |context| context.response.print "first" }
      second_server = HTTP::Server.new { |context| context.response.print "second" }
      begin
        Amber::Server.bind_unix_socket(first_server, socket_path)
        spawn(name: "first unix socket spec server") { first_server.listen }
        Fiber.yield

        expect_raises(Socket::BindError, /in use by another running server/) do
          Amber::Server.bind_unix_socket(second_server, socket_path)
        end

        response = HTTP::Client.new(UNIXSocket.new(socket_path)).get("/")
        response.body.should eq "first"
      ensure
        first_server.close
        second_server.close
        File.delete?(socket_path)
        File.delete?("#{socket_path}.lock")
      end
    end
  end

  describe "#check_listener_settings!" do
    it "rejects a UNIX socket with more than one process before the server forks" do
      with_listener_settings(unix_socket: "/run/app.sock", process_count: 2) do
        expect_raises(Amber::Exceptions::ConfigurationError, /process_count/) do
          Amber::Server.instance.check_listener_settings!
        end
      end
    end

    it "rejects a UNIX socket together with TLS" do
      with_listener_settings(unix_socket: "/run/app.sock", ssl_files: __FILE__) do
        expect_raises(Amber::Exceptions::ConfigurationError, /server.ssl/) do
          Amber::Server.instance.check_listener_settings!
        end
      end
    end

    it "accepts a UNIX socket with one process and no TLS" do
      with_listener_settings(unix_socket: "/run/app.sock") do
        Amber::Server.instance.check_listener_settings!
      end
    end

    it "accepts several processes on TCP" do
      with_listener_settings(unix_socket: nil, process_count: 4) do
        Amber::Server.instance.check_listener_settings!
      end
    end
  end
end
