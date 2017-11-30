require "http"
require "logger"
require "json"
require "colorize"
require "secure_random"
require "kilt"
require "kilt/slang"
require "redis"
require "./amber/version"
require "./amber/controller/**"
require "./amber/dsl/**"
require "./amber/exceptions/**"
require "./amber/extensions/**"
require "./amber/router/**"
require "./amber/server/**"
require "./amber/validations/**"
require "./amber/websockets/**"

module Amber
  SECRET_KEY          = "AMBER_ENCRYPTION_KEY"
  SECRET_FILE         = "./.encryption_key"
  CURRENT_ENVIRONMENT = ENV["AMBER_ENV"] ||= "development"

  alias EnvType = String | Symbol
  class_property environment_path = "./config/environments/"

  def self.settings
    # TODO: @@settings should be stored here instead of Amber::Server so we can use it in the CLI.
    Amber::Server.instance.settings
  end

  def self.logger
    settings.logger
  end

  # TODO: Should be moved to file encryption module.
  def self.secret_key
    ENV[SECRET_KEY]? || begin
      File.open(SECRET_FILE).gets_to_end.to_s if File.exists?(SECRET_FILE)
    end
  end

  def self.env=(env : EnvType)
    ENV["AMBER_ENV"] = env.to_s
    Amber::Server.instance.settings = EnvironmentLoader.new(env, @@environment_path).settings
  end

  def self.env
    @@env ||= Environment.new(CURRENT_ENVIRONMENT)
  end
end
