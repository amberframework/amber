module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < Command
      class Options
        arg "env", desc: "environment file to encrypt", default: "production"
        string ["-e", "--editor"], desc: "preferred editor: [vim, nano, pico, etc]", default: ENV.fetch("EDITOR", "vim")
        bool ["--noedit"], desc: "skip editing and just encrypt", default: false
        help
      end

      class Help
        header "Encrypts environment YAML file."
        caption "encrypts environment YAML file"
      end

      def run
        env = args.env
        encrypted_file = "config/environments/.#{env}.enc"
        unencrypted_file = "config/environments/#{env}.yml"

        unless File.exists?(unencrypted_file) || File.exists?(encrypted_file)
          raise Exceptions::Environment.new("./config/environments/", env)
        end

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, Support::FileEncryptor.read(encrypted_file))
          Process.run(options.editor, [unencrypted_file], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit) unless options.noedit?
        end

        if File.exists?(unencrypted_file)
          Support::FileEncryptor.write(encrypted_file, File.read(unencrypted_file))
          File.delete(unencrypted_file)
        end
      rescue e : Exception
        if ENV["AMBER_ENV"]? == "test" || ENV["CRYSTAL_CLI_ENV"]? == "test"
          raise e
        else
          exit! e.message, error: true
        end
      end
    end
  end
end
