require "./cluster"
require "./ssl"

module Amber
  class Server
    Log = ::Log.for(self)
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::MemoryAdapter.class
    property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    property adapter_based_pubsub : Amber::Adapters::PubSubAdapter? = nil
    getter handler = Pipe::Pipeline.new
    getter router = Router::Router.new

    def self.instance
      @@instance ||= new
    end

    def self.start
      instance.run
    end

    # Configure should probably be deprecated in favor of settings.
    def self.configure(&)
      with self yield instance.settings
    end

    def self.pubsub_adapter
      # Return adapter-based pub/sub if configured, otherwise fallback to legacy
      if instance.adapter_based_pubsub
        instance.adapter_based_pubsub.not_nil!
      else
        instance.pubsub_adapter.instance
      end
    end

    # Initialize adapters based on configuration
    def initialize_adapters
      # Initialize pub/sub adapter based on configuration
      pubsub_config = settings.pubsub
      adapter_name = pubsub_config[:adapter]

      if adapter_name && adapter_name != "legacy"
        @adapter_based_pubsub = Amber::Adapters::AdapterFactory.create_pubsub_adapter(adapter_name)
      end
    end

    def self.router
      instance.router
    end

    def self.handler
      instance.handler
    end

    # Returns all registered routes as structured data for introspection.
    def self.all_routes : Array(Router::RouteInfo)
      instance.router.all_routes
    end

    def initialize
      initialize_adapters
    end

    def project_name
      @project_name ||= settings.name.gsub(/\W/, "_").downcase
    end

    def run
      check_listener_settings!
      thread_count = settings.process_count
      if Cluster.master? && thread_count > 1
        thread_count.times { Cluster.fork }
        sleep
      else
        start
      end
    end

    def start
      check_listener_settings!
      time = Time.local
      Log.info { "#{paint(version, :light_cyan)} serving application \"#{settings.name.capitalize}\" at #{paint(host_url, :light_cyan).mode(:underline)}" }
      handler.prepare_pipelines
      server = HTTP::Server.new(handler)

      if socket_path = unix_socket_path
        self.class.bind_unix_socket(server, socket_path)
      elsif ssl_enabled?
        ssl_config = Amber::SSL.new(settings.ssl_key_file.not_nil!, settings.ssl_cert_file.not_nil!).generate_tls
        server.bind_tls Amber.settings.host, Amber.settings.port, ssl_config, settings.port_reuse
      else
        server.bind_tcp Amber.settings.host, Amber.settings.port, settings.port_reuse
      end

      # Crystal does not implement Signal#trap on Windows. Windows services and
      # console processes are stopped by their host, so only install Amber's
      # graceful Ctrl-C handler on platforms where the runtime supports it.
      {% unless flag?(:win32) %}
        Signal::INT.trap do
          Signal::INT.reset
          Log.info { "Shutting down Amber" }
          server.close
        end
      {% end %}

      loop do
        begin
          Log.info { "Server started in #{paint(Amber.env, :yellow)}." }
          Log.info { paint("Startup Time #{Time.local - time}", :white) }
          server.listen
          break
        rescue e : IO::Error
          Log.error(exception: e) { "Restarting server..." }
          sleep 1.second
        end
      end
    end

    def version
      "Amber #{Amber::VERSION}"
    end

    def host_url
      if socket_path = unix_socket_path
        "unix://#{socket_path}"
      else
        "#{scheme}://#{settings.host}:#{settings.port}"
      end
    end

    # The `server.unix_socket` path, when the server listens on one.
    private def unix_socket_path : String?
      server_config = settings.server
      server_config.unix_socket if server_config.listens_on_unix_socket?
    end

    # Raises `Amber::Exceptions::ConfigurationError` before the server forks
    # or binds when `server.unix_socket` is combined with TLS or with more
    # than one process. The settings are read as they stand at start, after
    # the environment file, `AMBER_*` variables and `config/settings.cr`.
    def check_listener_settings! : Nil
      return unless unix_socket_path

      Amber::Configuration::ServerConfig.check_unix_socket!(settings.server_terminates_tls?, settings.process_count)
    end

    # :nodoc:
    #
    # Binds *server* to the UNIX socket at *socket_path*, replacing a socket
    # file a stopped server left behind. The check, the removal and the bind
    # run under an exclusive lock on `<socket_path>.lock`, so two servers
    # starting on one path at once cannot both see the old socket as stale
    # and one remove the socket the other has just bound.
    def self.bind_unix_socket(server : HTTP::Server, socket_path : String) : Socket::UNIXAddress
      File.open("#{socket_path}.lock", "a") do |lock_file|
        lock_file.flock_exclusive do
          remove_stale_unix_socket(socket_path)
          server.bind_unix(socket_path)
        end
      end
    end

    # :nodoc:
    #
    # A previous run leaves its socket file behind, and binding over it fails.
    # Only a socket that no server accepts connections on is removed: a socket
    # another running server still listens on raises `Socket::BindError`
    # instead of being taken over, and any other file at the path is left
    # alone so that the bind reports the conflict.
    def self.remove_stale_unix_socket(socket_path : String) : Nil
      socket_info = File.info?(socket_path, follow_symlinks: false)
      return unless socket_info
      return unless socket_info.type.socket?

      if unix_socket_accepts_connections?(socket_path)
        raise Socket::BindError.new("server.unix_socket #{socket_path} is in use by another running server")
      end

      File.delete(socket_path)
    end

    # Returns `true` when a server accepts connections on *socket_path*, and
    # `false` when the socket refuses them, which is what a socket file left
    # behind by a stopped server does.
    private def self.unix_socket_accepts_connections?(socket_path : String) : Bool
      probe = UNIXSocket.new(socket_path)
      probe.close
      true
    rescue error : Socket::ConnectError
      raise error unless error.os_error == Errno::ECONNREFUSED

      false
    end

    def ssl_enabled?
      settings.ssl_key_file && settings.ssl_cert_file
    end

    def scheme
      ssl_enabled? ? "https" : "http"
    end

    def settings
      Amber.settings
    end

    private def paint(value, color)
      Support::LogColor.paint(value, color, settings.logging.colorize)
    end
  end
end
