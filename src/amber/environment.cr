require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    AMBER_ENV = "AMBER_ENV"
    class_property environment_path : String = "./config/environments/"

    @@settings : Settings?

    def self.settings
      @@settings ||= Loader.new(env.to_s, environment_path).settings
    end

    def self.logger
      settings.logger
    end

    def self.env=(env : EnvType)
      ENV[AMBER_ENV] = env.to_s
      @@settings = Loader.new(env, environment_path).settings
    end

    def self.env
      @@env ||= Env.new(current_environment)
    end
    
    def self.current_environment
      ENV[AMBER_ENV]? || "development"
    end
  end
end
