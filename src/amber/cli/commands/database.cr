require "micrate"
require "pg"
require "mysql"
require "sqlite3"

module Amber::CLI
  CLI.logger.progname = "Database"
  Micrate.logger = settings.logger
  Micrate.logger.progname = "Database"
  Micrate.logger.level = Logger::DEBUG

  class MainCommand < ::Cli::Supercommand
    command "db", aliased: "database"

    class Database < Command
      command_name "database"
      MIGRATIONS_DIR = "./db/migrations"

      class Options
        arg_array "commands", desc: "drop create migrate rollback redo status version seed"
        bool "--no-color", desc: "# Disable colored output", default: false
        help
      end

      class Help
        header <<-EOS
          Performs database migrations and maintenance tasks. Powered by micrate (https://github.com/juanedi/micrate)

        Commands:
          drop      # Drops the database
          create    # Creates the database
          migrate   # Migrate the database to the most recent version available
          rollback  # Roll back the database version by 1
          redo      # Re-run the latest database migration
          status    # dump the migration status for the current database
          version   # Print the current version of the database
          seed      # Initialize the database with seed data
        EOS
        caption "# Performs database migrations and maintenance tasks"
      end

      def run
        CLI.toggle_colors(options.no_color?)

        if args.commands.empty?
          connect_to_database
        end

        args.commands.each do |command|
          Micrate::DB.connection_url = database_url
          case command
          when "drop"
            Micrate.logger.info drop_database
          when "create"
            Micrate.logger.info create_database
          when "seed"
            Helpers.run("crystal db/seeds.cr", wait: true, shell: true)
            Micrate.logger.info "Seeded database"
          when "migrate"
            begin
              Micrate::Cli.run_up
            rescue e : IndexError
              exit! "No migrations to run in #{MIGRATIONS_DIR}."
            end
          when "rollback"
            Micrate::Cli.run_down
          when "redo"
            Micrate::Cli.run_redo
          when "status"
            Micrate::Cli.run_status
          when "version"
            Micrate::Cli.run_dbversion
          when "connect"
            connect_to_database
          else
            exit! help: true, error: false
          end
        end
      rescue e : Micrate::UnorderedMigrationsException
        exit! Micrate::Cli.report_unordered_migrations(e.versions), error: true
      rescue e : DB::ConnectionRefused
        exit! "Connection unsuccessful: #{Micrate::DB.connection_url.colorize(:light_blue)}", error: true
      rescue e : Exception
        exit! e.message, error: true
      end

      private def drop_database
        url = Micrate::DB.connection_url.to_s
        if url.starts_with? "sqlite3:"
          path = url.gsub("sqlite3:", "")
          File.delete(path)
          "Deleted file #{path}"
        else
          name = set_database_to_schema url
          Micrate::DB.connect do |db|
            db.exec "DROP DATABASE IF EXISTS #{name};"
          end
          "Dropped database #{name}"
        end
      end

      private def create_database
        url = Micrate::DB.connection_url.to_s
        if url.starts_with? "sqlite3:"
          puts <<-MSG
          No migration files were found. For sqlite3, the database will be created during the first migration.
          MSG
        else
          name = set_database_to_schema url
          Micrate::DB.connect do |db|
            db.exec "CREATE DATABASE #{name};"
          end
          "Created database #{name}"
        end
      end

      private def set_database_to_schema(url)
        uri = URI.parse(url)
        if path = uri.path
          Micrate::DB.connection_url = url.gsub(path, "/#{uri.scheme}")
          return path.gsub("/", "")
        else
          CLI.logger.info "Could not determine database name", "Error", :red
        end
      end

      private def connect_to_database
        Process.exec(command_line_tool, {database_url}) if database_url
        exit! error: false
      end

      private def command_line_tool
        case Amber::CLI.config.database
        when "pg"
          "psql"
        when "mysql"
          "mysql"
        when "sqlite"
          "sqlite3"
        else
          exit! "invalid database configuration", error: true
        end
      end

      private def database_url
        ENV["DATABASE_URL"]? || CLI.settings.database_url
      end
    end
  end
end
