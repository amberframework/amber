require "./logger"
require "yaml"

module Amber::Environment
  class Settings
    alias LoggingType = NamedTuple(severity: String, color: Bool, time: Bool, level: Bool)

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
    property logger : Amber::Environment::Logger = Logger.new(STDOUT)


    YAML.mapping(
      logging: {type: LoggingType, default: {
        severity: "info", color: true, time: false, level: false,
      }},
      database_url: {type: String?, default: nil},
      host: {type: String, default: "localhost"},
      name: {type: String, default: "Amber_App"},
      port: {type: Int32, default: 3000},
      port_reuse: {type: Bool, default: true},
      process_count: {type: Int32, default: 1},
      redis_url: {type: String?, default: nil},
      secret_key_base: {type: String, default: SecureRandom.urlsafe_base64(32)},
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

    def logger
      return @logger unless @logger
      @logger = Logger.new(STDOUT)
      @logger.level = logging.severity
      Colorize.enabled = logging.color
      @logger
    end

    def logging
      @_logging ||= Logging.new(@logging)
    end

    class Logging
      SEVERITY_MAP = {
        "debug": Logger::DEBUG,
        "info": Logger::INFO,
        "warn": Logger::WARN,
        "error": Logger::ERROR,
        "fatal": Logger::FATAL,
        "unknown": Logger::UNKNOWN
      }
      property color : Bool
      property time : Bool
      property level : Bool
      property log_level : String

      def initialize(logging : LoggingType)
        @color = logging[:color]
        @time = logging[:time]
        @level = logging[:level]
        @log_level = logging[:severity]
      end

      def severity
        SEVERITY_MAP[log_level]
      end
    end
  end
end
