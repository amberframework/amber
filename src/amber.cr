require "http"
require "logger"
require "./amber/*"
require "./amber/pipe/*"

module Amber
  class Server
    property :port
    property name : String
    property env : String
    property log : ::Logger

    def self.instance
      @@instance ||= new
    end

    def initialize(app_path : String = __FILE__)
      @app_path = app_path
      @name = "My Awesome App"
      @port = 8080
      @env = "development".colorize(:yellow).to_s
      @log = ::Logger.new(STDOUT)
      @log.level = ::Logger::INFO
      @pipes : Array(Http::Handler)
    end

    def run(port : Int = 4000)
      time = Time.now
      host = "127.0.0.1"
      @port = port.to_i

      str_host = "http://#{host}:#{@port}".colorize(:light_cyan).underline
      version = "[Amber #{Amber::VERSION}]".colorize(:light_cyan).to_s

      log.info "#{version} serving application \"#{@name}\" at #{str_host}".to_s

      server = HTTP::Server.new(host, port, pipeline)

      Signal::INT.trap do
        server.close
        exit
      end

      log.info "Server started in #{@env}.".to_s
      log.info "Startup Time #{Time.now - time}\n\n".colorize(:white).to_s
      server.listen
    end


    def draw(&block)
      router.draw(&block)
    end

    def router
      Pipe::Router.instance
    end
  end
end


class EliasController < Amber::Controller
  def perez
    "Nice framework Elias!"
  end
end

MyAwesomeApp = Amber::Server.instance

MyAwesomeApp.draw do
  pipeline :api do
    connect Pipe::Logger.instance
    connect Pipe::Router.instance
  end

  get "/", :elias, :perez
  get "/elias", :elias, :perez
  get "/elias/:role", :elias, :perez
end

MyAwesomeApp.run

