require "../../support/message_encryptor"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "encrypt", aliased: "enc"

    class Secrets < ::Cli::Command
      class Options
        arg "env", desc: "file to encrypt", default: "production"
      end

      class Help
        caption "# Encrypts Secrets."
      end

      def run
        secret_key = ENV["AMBER_SECRET_KEY"]? || File.open(".amber_secret_key").gets_to_end.to_s
        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)
        if File.exists?(fn = "./config/environments/#{args.env}.yml")
          File.write("./config/environments/.#{args.env}.enc", enc.encrypt(File.read(fn)))
          File.delete(fn)
        elsif File.exists?(fn = "./config/environments/.#{args.env}.enc")
          File.write("./config/environments/production.yml", enc.decrypt(File.open(fn).gets_to_end.to_slice))
          File.delete(fn)
        else
          puts "Ooops! Your environment file doesn't exist!"
        end
      end
    end
  end
end
