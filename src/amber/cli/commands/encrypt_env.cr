require "../../support/message_encryptor"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "enc", aliased: "encrypt_env"

    class EncryptEnv < ::Cli::Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
      end

      class Help
        caption "# Encrypts Environment"
      end

      def run
        secret_key = ENV["AMBER_SECRET_KEY"]? || File.open(".amber_secret_key").gets_to_end.to_s
        env = ENV["AMBER_ENV"]? || args.env
        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)
        if File.exists?(fn = "./config/environments/#{env}.yml")
          File.write("./config/environments/.#{env}.enc", enc.encrypt(File.read(fn)))
          File.delete(fn)
        elsif File.exists?(fn = "./config/environments/.#{env}.enc")
          File.write("./config/environments/#{env}.yml", enc.decrypt(File.open(fn).gets_to_end.to_slice))
          File.delete(fn)
        else
          puts "Ooops! Your environment file doesn't exist!"
        end
      rescue
        puts "Failed! Are you sure your key is correct?"
      end
    end
  end
end
