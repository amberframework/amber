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
        migrations_path, migrations_table_suffix = Micrate::Cli.parse_command_arguments
        Micrate::Cli.setup_logger
        Micrate::DB.connection_url = database_url
        begin
          case args.command
          when "up"
            Micrate::Cli.run_up(migrations_path, migrations_table_suffix)
          when "down"
            Micrate::Cli.run_down(migrations_path, migrations_table_suffix)
          when "redo"
            Micrate::Cli.run_redo(migrations_path, migrations_table_suffix)
          when "status"
            Micrate::Cli.run_status(migrations_path, migrations_table_suffix)
          when "dbversion"
            Micrate::Cli.run_dbversion(migrations_table_suffix)
          else
            Micrate::Cli.print_help
          end
        rescue e : Micrate::UnorderedMigrationsException
          Micrate::Cli.report_unordered_migrations(e.versions, migrations_path)
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
