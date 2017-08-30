require "micrate"
require "pg"
require "mysql"
require "sqlite3"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "m", aliased: "migrate"
    command "micrate", aliased: "migrate"

    class Migrate < ::Cli::Command
      command_name "migrate"

      class Options
        arg "command", desc: "up, down, redo, status, dbversion", required: true
      end

      class Help
        caption "# Performs database migrations tasks"
      end

      def run
        Micrate::Cli.setup_logger
        Micrate::DB.connection_url = database_url
        begin
          case args.command
          when "up"
            Micrate::Cli.run_up
          when "down"
            Micrate::Cli.run_down
          when "redo"
            Micrate::Cli.run_redo
          when "status"
            Micrate::Cli.run_status
          when "dbversion"
            Micrate::Cli.run_dbversion
          else
            Micrate::Cli.print_help
          end
        rescue e : Micrate::UnorderedMigrationsException
          Micrate::Cli.report_unordered_migrations(e.versions)
          exit 1
        rescue e : DB::ConnectionRefused
          puts "Connection refused: #{Micrate::DB.connection_url}"
          exit 1
        rescue e : Exception
          puts e.message
          exit 1
        end
      end

      def database_url
        ENV["DATABASE_URL"]? || begin
          yaml_file = File.read("config/database.yml")
          yaml = YAML.parse(yaml_file)
          db = yaml.first.to_s
          settings = yaml[db]
          env(settings["database"].to_s)
        end
      end

      private def env(value)
        env_var = value.gsub("${", "").gsub("}", "")
        if ENV.has_key? env_var
          return ENV[env_var]
        else
          return value
        end
      end
    end
  end
end
