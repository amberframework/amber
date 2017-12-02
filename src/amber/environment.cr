require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    CURRENT_ENVIRONMENT = ENV["AMBER_ENV"] ||= "development"
    class_property environment_path : String = "./config/environments/"

    @@_settings : Settings?

    def self.settings
      @@_settings ||= Loader.new(CURRENT_ENVIRONMENT, @@environment_path).settings
    end

    def self.logger
      settings.logger
    end

    def self.env=(env : EnvType)
      ENV["AMBER_ENV"] = env.to_s
      @@_settings = Loader.new(env, @@environment_path).settings
    end

    def self.env
      @@env ||= Env.new(CURRENT_ENVIRONMENT)
    end
  end
end
