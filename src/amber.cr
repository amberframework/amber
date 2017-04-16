require "http"
require "logger"
require "./amber/*"
require "./amber/pipe/*"

module Amber
  class Server
    setter port : Int32
    setter name : String
    setter env : String
    getter log : ::Logger

    def self.instance
      @@instance ||= new
    end

    def initialize
      @app_path = __FILE__
      @name = "My Awesome App"
      @port = 8080
      @env = "development".colorize(:yellow).to_s
      @log = ::Logger.new(STDOUT)
      @log.level = ::Logger::INFO
    end

    def run(port : Int = 4000)
      time = Time.now
      host = "127.0.0.1"
      @port = port.to_i

      str_host = "http://#{host}:#{@port}".colorize(:light_cyan).underline
      version = "[Amber #{Amber::VERSION}]".colorize(:light_cyan).to_s

      log.info "#{version} serving application \"#{@name}\" at #{str_host}".to_s

      server = HTTP::Server.new(host, port, handler)

      Signal::INT.trap do
        puts "Shutting down Amber"
        server.close
        exit
      end

      log.info "Server started in #{@env}.".to_s
      log.info "Startup Time #{Time.now - time}\n\n".colorize(:white).to_s
      server.listen
    end

    def config
      with self yield
    end

    def routes(&block)
      router.draw(&block)
    end

    def pipeline(valve : Symbol, &block)
      handler.build valve, &block
    end

    def handler
      Pipe::Pipeline.instance
    end

    private def router
      Pipe::Router.instance
    end
  end
end
