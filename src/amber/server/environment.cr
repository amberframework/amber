require "yaml"
require "secure_random"
require "../support/message_encryptor"

module Amber
  class Environment
    AMBER_SECRET_KEY  = "AMBER_SECRET_KEY"
    AMBER_SECRET_FILE = ".amber_secret_key"
    private getter yaml_settings : String
    private getter encrypted_settings : String
    private getter default_path : String
    private getter environment : String

    def self.load(path, env)
      new(path, env).settings
    end

    def initialize(@default_path, @environment)
      @yaml_settings = environment_file(".yml")
      @encrypted_settings = environment_file(".enc")
      raise "Environment file not found! #{yaml_settings}#{encrypted_settings}" unless env_settings_exists?
    end

    def settings
      settings = Settings.from_yaml(environment_settings.to_s)
      settings.env = environment
      settings
    end

    private def env_path
      return default_path if Dir.exists?(default_path)
      # TODO Remove, it should not be implicitly loading test environment settings
      load_test_environment
    end

    private def secret_key
      return ENV[AMBER_SECRET_FILE]? if ENV[AMBER_SECRET_KEY]?
      File.open(AMBER_SECRET_FILE).gets_to_end.to_s if File.exists?(AMBER_SECRET_FILE)
    end

    private def environment_file(ext)
      "#{env_path}/#{environment}#{ext}"
    end

    private def environment_settings
      return File.read(yaml_settings) if File.exists?(yaml_settings)

      if File.exists?(encrypted_settings) && !secret_key.nil?
        enc = Amber::Support::MessageEncryptor.new(secret_key.not_nil!.to_slice)
        String.new(enc.decrypt(File.open(encrypted_settings).gets_to_end.to_slice))
      end
    end

    private def env_settings_exists?
      File.exists?(yaml_settings) || File.exists?(encrypted_settings)
    end

    private def load_test_environment
      environment = ARGV[0]? || "test"
      "./spec/support/config"
    end
  end
end
