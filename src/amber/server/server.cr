module Amber
  class Server
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class
    property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    property settings : Amber::Settings
    getter handler = Pipe::Pipeline.new
    getter router = Router::Router.new

    def self.instance
      @@instance ||= new(Amber.settings)
    end

    def self.start
      instance.run
    end

    # Configure should probably be deprecated in favor of settings.
    def self.configure
      with self yield settings
    end

    def self.settings
      instance.settings
    end

    def self.pubsub_adapter
      instance.pubsub_adapter.instance
    end

    def self.router
      instance.router
    end

    def self.handler
      instance.handler
    end

    def initialize(@settings)
      settings.log.level = ::Logger::INFO
    end

    def project_name
      @project_name ||= settings.name.gsub(/\W/, "_").downcase
    end

    def run
      thread_count = settings.process_count
      if Cluster.master? && thread_count > 1
        while (thread_count > 0)
          Cluster.fork ({"id" => thread_count.to_s})
          thread_count -= 1
        end
        sleep
      else
        start
      end
    end

    def start
      time = Time.now
      settings.log.info "#{version} serving application \"#{settings.name}\" at #{host_url}".to_s
      handler.prepare_pipelines
      server = HTTP::Server.new(settings.host, settings.port, handler)
      server.tls = Amber::SSL.new(settings.ssl_key_file.not_nil!, settings.ssl_cert_file.not_nil!).generate_tls if ssl_enabled?

      Signal::INT.trap do
        settings.log.info "Shutting down Amber"
        server.close
        exit
      end

      settings.log.info "Server started in #{colorize(Amber.env, :yellow)}."
      settings.log.info colorize("Startup Time #{Time.now - time}\n\n", :white)
      server.listen(settings.port_reuse)
    end

    private def version
      colorize("[Amber #{Amber::VERSION}]", :light_cyan)
    end

    private def host_url
      colorize("#{scheme}://#{settings.host}:#{settings.port}", :light_cyan, :underline)
    end

    private def ssl_enabled?
      settings.ssl_key_file && settings.ssl_cert_file
    end

    private def scheme
      ssl_enabled? ? "https" : "http"
    end

    def colorize(text, color)
      text.colorize(color).toggle(settings.colorize_logging).to_s
    end

    def colorize(text, color, mode)
      text.colorize(color).toggle(settings.colorize_logging).mode(mode).to_s
    end
  end
end
