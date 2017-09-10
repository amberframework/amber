require "../../support/message_encryptor"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < ::Cli::Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
        string ["-e", "--editor"], desc: "Prefered Editor: [vim, nano, pico, etc]", default: "vim"
        bool ["--noedit"], desc: "Skip editing and just encrypt", default: false
      end

      class Help
        caption "# Encrypts Environment"
      end

      def run
        secret_key = ENV["AMBER_SECRET_KEY"]? || File.open(".amber_secret_key").gets_to_end.to_s
        env = args.env
        encrypted_file = "config/environments/.#{env}.enc"
        unencrypted_file = "config/environments/#{env}.yml"

        enc = Amber::Support::MessageEncryptor.new(secret_key)

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, enc.decrypt(File.open(encrypted_file).gets_to_end.to_slice))
          system("#{options.editor} #{unencrypted_file}") unless options.noedit?
        end

        if File.exists?(unencrypted_file)
          File.write(encrypted_file, enc.encrypt(File.read(unencrypted_file)))
          File.delete(unencrypted_file)
        else
          puts "#{env}.yml doesn't exist. Loading defaults!"
        end
      rescue
        puts "Failed! Make sure to set AMBER_SECRET_KEY env or add hidden file .amber_secret_key"
      end
    end
  end
end
