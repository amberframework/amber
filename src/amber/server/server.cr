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
      thread_count = settings.process_count
      if Cluster.master? && thread_count > 1
        thread_count.times { Cluster.fork }
        sleep
      else
        start
      end
    end

    def start
      time = Time.local
      Log.info { "#{version.colorize(:light_cyan)} serving application \"#{settings.name.capitalize}\" at #{host_url.colorize(:light_cyan).mode(:underline)}" }
      handler.prepare_pipelines
      server = HTTP::Server.new(handler)

      if ssl_enabled?
        ssl_config = Amber::SSL.new(settings.ssl_key_file.not_nil!, settings.ssl_cert_file.not_nil!).generate_tls
        server.bind_tls Amber.settings.host, Amber.settings.port, ssl_config, settings.port_reuse
      else
        server.bind_tcp Amber.settings.host, Amber.settings.port, settings.port_reuse
      end

      Signal::INT.trap do
        Signal::INT.reset
        Log.info { "Shutting down Amber" }
        server.close
      end

      loop do
        begin
          Log.info { "Server started in #{Amber.env.colorize(:yellow)}." }
          Log.info { "Startup Time #{Time.local - time}".colorize(:white) }
          server.listen
          break
        rescue e : IO::Error
          Log.error(exception: e) { "Restarting server..." }
          sleep 1
        end
      end
    end

    def version
      "Amber #{Amber::VERSION}"
    end

    def host_url
      "#{scheme}://#{settings.host}:#{settings.port}"
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
  end
end
