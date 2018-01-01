require "./logger"
require "yaml"

module Amber::Environment
  class Settings
    alias LoggingType = NamedTuple(
      severity: String,
      colorize: Bool,
      filter: Array(String?),
      skip: Array(String?),
      context: Array(String?))

    setter session : Hash(String, Int32 | String)
    property logging : LoggingType
    property database_url : String
    property host : String
    property name : String
    property port : Int32
    property port_reuse : Bool
    property process_count : Int32
    property redis_url
    property secret_key_base : String
    property secrets : Hash(String, String)
    property ssl_key_file : String
    property ssl_cert_file : String
    property logger : Logger?

    def logger
      @logger ||= LoggerBuilder.new(STDOUT, logging).logger
    end

    YAML.mapping(
      logging: {type: LoggingType, default: {
        severity: "debug",
        colorize: true,
        filter:   ["password", "confirm_password"] of String?,
        skip:     [] of String?,
        context:  ["request", "headers", "cookies", "session", "params"] of String?,
      }},
      database_url: {type: String?, default: nil},
      host: {type: String, default: "localhost"},
      name: {type: String, default: "Amber_App"},
      port: {type: Int32, default: 3000},
      port_reuse: {type: Bool, default: true},
      process_count: {type: Int32, default: 1},
      redis_url: {type: String?, default: nil},
      secret_key_base: {type: String, default: Random::Secure.urlsafe_base64(32)},
      secrets: {type: Hash(String, String)?, default: nil},
      session: {type: Hash(String, Int32 | String), default: {
        "key" => "amber.session", "store" => "signed_cookie", "expires" => 0,
      }},
      ssl_key_file: {type: String?, default: nil},
      ssl_cert_file: {type: String?, default: nil},
    )

    def session
      {
        :key     => @session["key"].to_s,
        :store   => session_store,
        :expires => @session["expires"].to_i,
      }
    end

    def session_store
      case @session["store"].to_s
      when "signed_cookie" then :signed_cookie
      when "redis"         then :redis
      else                      "encrypted_cookie"
      :encrypted_cookie
      end
    end

    def logging
      @_logging ||= Logging.new(@logging)
    end
  end

  class LoggerBuilder
    def self.logger(io, logging)
      new(io, logging).logger
    end

    def initialize(io, logging)
      Colorize.enabled = logging.colorize
      @logger = Environment::Logger.new(io)
      @logger.level = logging.severity
      @logger.progname = "Server"
      @logger.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
        io << datetime.to_s("%I:%M:%S")
        io << " (#{severity})" if severity > Logger::DEBUG
        io << " "
        io << progname
        io << " "
        io << message
      end
    end

    def logger
      @logger
    end
  end

  class Logging
    SEVERITY_MAP = {
      "debug":   Logger::DEBUG,
      "info":    Logger::INFO,
      "warn":    Logger::WARN,
      "error":   Logger::ERROR,
      "fatal":   Logger::FATAL,
      "unknown": Logger::UNKNOWN,
    }

    setter severity : String
    property colorize : Bool
    property context : Array(String?)
    property skip : Array(String?)
    property filter : Array(String?)

    def initialize(logging : Settings::LoggingType)
      @colorize = logging[:colorize]
      @severity = logging[:severity]
      @filter = logging[:filter]
      @skip = logging[:skip]
      @context = logging[:context]
    end

    def severity
      SEVERITY_MAP[@severity]
    end

    def logger
      @logger
    end
  end
end
