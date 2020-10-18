module Launch::CLI
  class MainCommand < ::Cli::Supercommand
    command "e", aliased: "encrypt"

    class Encrypt < Command
      class Options
        string ["-e", "--editor"], desc: "preferred editor: [vim, nano, pico, etc]", default: ENV.fetch("EDITOR", "vim")
        bool ["--noedit"], desc: "skip editing and just encrypt", default: false
        help
      end

      class Help
        header "Encrypts environment YAML file."
        caption "encrypts environment YAML file"
      end

      def run
        encrypted_file = "config/credentials.yml.enc"
        unencrypted_file = "config/credentials.yml"

        unless File.exists?(unencrypted_file) || File.exists?(encrypted_file)
          raise Exceptions::Environment.new("./config/credentials.yml.", "enc")
        end

        if File.exists?(encrypted_file)
          File.write(unencrypted_file, Support::FileEncryptor.read(encrypted_file))
          system("#{options.editor} #{unencrypted_file}") unless options.noedit?
        end

        if File.exists?(unencrypted_file)
          Support::FileEncryptor.write(encrypted_file, File.read(unencrypted_file))
          File.delete(unencrypted_file)
        end
      rescue e : Exception
        exit! e.message, error: true
      end
    end
  end
end
