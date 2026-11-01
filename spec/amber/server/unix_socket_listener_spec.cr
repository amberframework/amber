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

    it "creates the socket so that only its owner and group may connect" do
      socket_path = File.tempname("amber-socket-mode", ".sock")
      server = HTTP::Server.new { |context| context.response.print "ok" }
      previous_umask = LibC.umask(0o000)
      begin
        Amber::Server.bind_unix_socket(server, socket_path)
        umask_after_bind = LibC.umask(0o000)

        File.info(socket_path).permissions.value.should eq Amber::Server::UNIX_SOCKET_MODE
        umask_after_bind.should eq 0o000
      ensure
        LibC.umask(previous_umask)
        server.close
        File.delete?(socket_path)
        File.delete?("#{socket_path}.lock")
      end
    end

    it "waits
 for the lock, so a server that binds first is never unlinked by a slower start" do
      socket_path = File.tempname("amber-bind-race", ".sock")
      winning_server = HTTP::Server.new { |context| context.response.print "winner" }
      waiting_server = HTTP::Server.new { |context| context.response.print "waiter" }
      outcome = Channel(Exception?).new(1)
      begin
        leave_stale_socket(socket_path)
        File.open("#{socket_path}.lock", "a") do |lock_file|
          lock_file.flock_exclusive do
            spawn(name: "waiting unix socket binder") do
              Amber::Server.bind_unix_socket(waiting_server, socket_path)
              outcome.send(nil)
            rescue error : Socket::BindError
              outcome.send(error)
            end
            sleep 50.milliseconds

            # The waiting start has not touched the stale socket while the
            # lock is held: without the lock it would have replaced it already.
            File.info(socket_path, follow_symlinks: false).type.socket?.should be_true
            expect_raises(Socket::ConnectError) { UNIXSocket.new(socket_path) }

            # Another start wins the race under the lock.
            File.delete(socket_path)
            winning_server.bind_unix(socket_path)
            spawn(name: "winning unix socket spec server") { winning_server.listen }
            Fiber.yield
          end
        end

        error = outcome.receive
        error.should be_a(Socket::BindError)
        HTTP::Client.new(UNIXSocket.new(socket_path)).get("/").body.should eq "winner"
      ensure
        winning_server.close
        waiting_server.close
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
