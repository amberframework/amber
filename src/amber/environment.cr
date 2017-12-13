require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    AMBER_ENV = "AMBER_ENV"
    class_property environment_path : String = "./config/environments/"
    Colorize.enabled = settings.colorize_logging

    @@settings : Settings?

    def self.settings
      @@settings ||= Loader.new(env.to_s, environment_path).settings
    end

    def self.logger
      settings.logger.formatter = Logger::Formatter.new do |severity, datetime, progname, message, io|
        io << datetime.to_s("%Y-%m-%d %I:%M:%S") + " " if severity > Logger::Severity::DEBUG && severity < Logger::Severity::UNKNOWN
        io << progname.rjust(justify)
        io << " "
        io << message
      end
      settings.logger
    end

    def self.env=(env : EnvType)
      ENV[AMBER_ENV] = env.to_s
			@@env =  Env.new(env.to_s)
			@@settings = Loader.new(env.to_s, environment_path).settings
    end

    def self.env
      @@env = Env.new(current_environment)
    end

    def self.current_environment
     ENV[AMBER_ENV]? || "development"
    end

    private def self.justify
      settings.colorize_logging ? 20 : 12
    end

    private def self.justify
      settings.colorize_logging ? 20 : 12
    end
  end
end
