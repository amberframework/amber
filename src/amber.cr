require "http"
require "logger"
require "json"
require "colorize"
require "secure_random"
require "kilt"
require "kilt/slang"
require "./amber/dsl/*"
require "./amber/support/*"
require "./amber/**"

module Amber
  class Server
    property port : Int32
    property name : String
    property env : String
    property log : Logger
    property secret : String

    def self.instance
      @@instance ||= new
    end

    def self.settings
      instance
    end

    def initialize
      @app_path = __FILE__
      @name = "My Awesome App"
      @port = 8080
      @env = "development".colorize(:yellow).to_s
      @log = ::Logger.new(STDOUT)
      @log.level = ::Logger::INFO
      @secret = SecureRandom.hex
    end

    def run
      time = Time.now
      host = "127.0.0.1"

      str_host = "http://#{host}:#{port}".colorize(:light_cyan).underline
      version = "[Amber #{Amber::VERSION}]".colorize(:light_cyan).to_s

      log.info "#{version} serving application \"#{name}\" at #{str_host}".to_s

      server = HTTP::Server.new(host, port, handler)

      Signal::INT.trap do
        puts "Shutting down Amber"
        server.close
        exit
      end

      log.info "Server started in #{env}.".to_s
      log.info "Startup Time #{Time.now - time}\n\n".colorize(:white).to_s
      server.listen
    end

    def config(&block)
      with self yield self
    end

    macro routes(valve, scope = "")
      router.draw {{valve}}, {{scope}} do
        {{yield}}
      end
    end

    def socket_endpoint(path, app_socket)
      WebSockets::Server.create_endpoint(path, app_socket)
    end

    macro pipeline(valve)
      handler.build {{valve}} do
        {{yield}}
      end
    end

    def handler
      Pipe::Pipeline.instance
    end

    private def router
      Pipe::Router.instance
    end
  end
end
