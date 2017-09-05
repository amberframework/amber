require "yaml"
require "secure_random"
require "../support/message_encryptor"

module Amber
  class Environment
    @default_path : String
    @environment : String

    def self.load(path, env)
      new(path, env).settings
    end

    def initialize(@default_path, @environment)
      raise "Environment file not found! #{environment_file}#{encrypted_env_file}" unless configuration_exists?
    end

    def settings
      settings = Settings.from_yaml(environment_yml.to_s)
      settings.env = @environment
      settings
    end

    # Eliminates the need for environment variables settings set before tests
    private def env_path
      # if config/environments doesn't exist look in spec folder and set env to test
      return @default_path if Dir.exists?(@default_path)
      @environment = ARGV[0]? || "test"
      "./spec/support/config"
    end

    private def secret_key
      return ENV["AMBER_SECRET_KEY"]? if ENV["AMBER_SECRET_KEY"]?
      if File.exists?(".amber_secret_key")
        File.open(".amber_secret_key").gets_to_end.to_s
      end
    end

    private def environment_file
      "#{env_path}/#{@environment}.yml"
    end

    private def encrypted_env_file
      "#{env_path}/.#{@environment}.enc"
    end

    private def environment_yml
      return File.read(environment_file) if File.exists?(environment_file)

      if File.exists?(encrypted_env_file) && secret_key
        enc = Amber::Support::MessageEncryptor.new(secret_key.not_nil!.to_slice)
        String.new(enc.decrypt(File.open(encrypted_env_file).gets_to_end.to_slice))
      end
    end

    private def configuration_exists?
      !File.exists?(environment_file) || !File.exists?(encrypted_env_file)
    end
  end
end
