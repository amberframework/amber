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

      class Options
        arg_array "commands", desc: "drop create migrate rollback redo status version seed"
        bool "--no-color", desc: "# Disable colored output", default: false
        help
      end

      class Help
        caption "# Performs database maintenance tasks"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        args.commands.each do |command|
          Micrate::DB.connection_url = database_url
          case command
          when "drop"
            Micrate.logger.info drop_database
          when "create"
            Micrate.logger.info create_database
          when "seed"
            `crystal db/seeds.cr`
            Micrate.logger.info "Seeded database"
          when "migrate"
            Micrate::Cli.run_up
          when "rollback"
            Micrate::Cli.run_down
          when "redo"
            Micrate::Cli.run_redo
          when "status"
            Micrate::Cli.run_status
          when "version"
            Micrate::Cli.run_dbversion
          else
            Micrate::Cli.print_help
          end
        end
      rescue e : Micrate::UnorderedMigrationsException
        exit! Micrate::Cli.report_unordered_migrations(e.versions), error: true
      rescue e : DB::ConnectionRefused
        exit! "Connection refused: #{Micrate::DB.connection_url.colorize(:light_blue)}", error: true
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
          CLI.logger.puts "Could not determine database name", "Error", :red
        end
      end

      private def database_url
        ENV["DATABASE_URL"]? || CLI.settings.database_url
      end
    end
  end
end
