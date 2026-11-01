require "./environment/**"
require "./support/file_encryptor"

module Amber::Environment
  alias EnvType = String | Symbol

  macro included
    class_property path : String = "./config/environments/"
    @@settings : Settings?

    def self.settings
      @@settings ||= Loader.new(env.to_s, path).settings
    rescue Amber::Exceptions::Environment
      @@settings = Settings.from_yaml("default: settings")
    end

    # Returns true once `settings` has been loaded. Sections registered after
    # this point are missing from the loaded settings.
    def self.settings_loaded? : Bool
      !@@settings.nil?
    end

    def self.env=(env : EnvType)
      @@env = Env.new(env.to_s)
      @@settings = Loader.new(env, path).settings
    end

    def self.env
      @@env ||= Env.new
    end
  end
end
