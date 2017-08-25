require "http"
require "logger"
require "json"
require "colorize"
require "secure_random"
require "kilt"
require "kilt/slang"
require "redis"
require "./amber/**"

module Amber
  class Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class

    property port_reuse = true
    property port = 8080
    property name = "amber_project"
    property env = ARGV[0]? || ENV["AMBER_ENV"]? || "development"
    property log = ::Logger.new(STDOUT)
    property host = "0.0.0.0"
    property ssl_key_file : String? = nil
    property ssl_cert_file : String? = nil
    property redis_url = ENV["REDIS_URL"]? || "localhost:6379"
    property secret = ENV["SECRET_KEY_BASE"]? || SecureRandom.hex(128)
    property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter

    property session = {
      :key => "amber.session", :store => :signed_cookie, :expires => 0, :secret => secret.to_s, :redis_url => redis_url.to_s,
    }

    getter key_generator = Amber::Support::CachingKeyGenerator.new(
      Amber::Support::KeyGenerator.new(secret.to_s, 5)
    )

    def initialize
      @log.level = ::Logger::INFO
    end

    def self.instance
      @@instance ||= new
    end

    def self.routes
      instance.all_routes
    end

    def self.config(&block)
      instance.config(block)
    end

    def self.key_generator
      instance.key_generator
    end

    def self.session
      instance.session
    end

    def project_name
      @project_name ||= @name.gsub(/\W/, "_").downcase
    end

    def run
      ENV["PROCESS_COUNT"] ||= "1"
      thread_count = ENV["PROCESS_COUNT"].to_i
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
      log.info "#{version} serving application \"#{name}\" at #{host}".to_s

      handler.prepare_pipelines

      server = HTTP::Server.new(host, port, handler)
      server.tls = Amber::SSL.new(ssl_key_file.not_nil!, ssl_cert_file.not_nil!).generate_tls if ssl_enabled?

      Signal::INT.trap do
        log.info "Shutting down Amber"
        server.close
        exit
      end

      log.info "Server started in #{env.colorize(:yellow)}.".to_s
      server.listen(port_reuse)
      log.info "Startup Time #{Time.now - time}\n\n".colorize(:white).to_s
    end

    def config(&block)
      with self yield self
    end

    def socket_endpoint(path, app_socket)
      WebSockets::Server.create_endpoint(path, app_socket)
    end

    macro routes(valve, scope = "")
      router.draw {{valve}}, {{scope}} do
        {{yield}}
      end
    end

    macro pipeline(valve)
      handler.build {{valve}} do
        {{yield}}
      end
    end

    private def version
      "[Amber #{Amber::VERSION}]".colorize(:light_cyan).to_s
    end

    private def host
      "#{scheme}://#{host}:#{port}".colorize(:light_cyan).underline
    end

    private def ssl_enabled?
      ssl_key_file && ssl_cert_file
    end

    private def scheme
      ssl_enabled? ? "https" : "http"
    end

    private def handler
      @handler ||= Pipe::Pipeline.new
    end

    private def router
      @router ||= Router::Router.instance
    end
  end

  class Cluster
    def self.fork(env : Hash)
      env["FORKED"] = "1"
      Process.fork { Process.run(PROGRAM_NAME, nil, env, true, false, true, true, true, nil) }
    end

    def self.master?
      (ENV["FORKED"]? || "0") == "0"
    end

    def self.worker?
      (ENV["FORKED"]? || "0") == "1"
    end
  end
end
