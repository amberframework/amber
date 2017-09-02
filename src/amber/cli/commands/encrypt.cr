require "../../support/message_encryptor"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < ::Cli::Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
        string ["-e", "--editor"], desc: "editor", default: "vim"
      end

      class Help
        caption "# Encrypts Environment"
      end

      def run
        secret_key = ENV["AMBER_SECRET_KEY"]? || File.open(".amber_secret_key").gets_to_end.to_s
        env = ENV["AMBER_ENV"]? || args.env
        encrypted_file = "config/environments/.#{env}.enc"
        unencrypted_file = "config/environments/#{env}.yml"

        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, enc.decrypt(File.open(encrypted_file).gets_to_end.to_slice))
          system("#{options.editor} #{unencrypted_file}")
        end

        if File.exists?(unencrypted_file)
          File.write(encrypted_file, enc.encrypt(File.read(unencrypted_file)))
          File.delete(unencrypted_file)
        else
          puts "Ooops! Your environment file doesn't exist!"
        end
      rescue
        puts "Failed! Are you sure your key is correct?"
      end
    end
  end
end
