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

      private def database_url
        ENV["DATABASE_URL"]? || begin
          yaml_file = File.read(ENV_CONFIG_PATH)
          yaml = YAML.parse(yaml_file)
          yaml["database_url"].to_s
        end
      end
    end
  end
end
