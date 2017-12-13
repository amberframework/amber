require "micrate"
require "pg"
require "mysql"
require "sqlite3"

module Amber::CLI
  class MainCommand < ::Cli::Supercommand
    command "db", aliased: "database"

    class Database < ::Cli::Command
      command_name "database"

      class Options
        arg_array "commands", desc: "drop create migrate rollback redo status version seed"
        help
      end

      class Help
        caption "# Performs database maintenance tasks"
      end

      def run
        args.commands.each do |command|
          Micrate::Cli.setup_logger
          Micrate::DB.connection_url = database_url
          case command
          when "drop"
            drop_database
          when "create"
            create_database
          when "seed"
            `crystal db/seeds.cr`
            log "Seeded database"
          when "migrate"
            log Micrate::Cli.run_up
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
        exit! "Connection refused: #{Micrate::DB.connection_url}", error: true
      rescue e : Exception
        exit! e.message, error: true
      end

      private def drop_database
        url = Micrate::DB.connection_url.to_s
        if url.starts_with? "sqlite3:"
          path = url.gsub("sqlite3:", "")
          File.delete(path)
          log "Deleted file #{path}"
        else
          name = set_database_to_schema url
          Micrate::DB.connect do |db|
            db.exec "DROP DATABASE IF EXISTS #{name};"
          end
          log "Dropped database #{name.colorize(:light_cyan)}"
        end
      end

      private def create_database
        url = Micrate::DB.connection_url.to_s
        if url.starts_with? "sqlite3:"
          log "For sqlite3, the database will be created during the first migration."
        else
          name = set_database_to_schema url
          Micrate::DB.connect do |db|
            db.exec "CREATE DATABASE #{name};"
          end
          log "Created database #{name.colorize(:light_cyan)}"
        end
      end

      private def set_database_to_schema(url)
        uri = URI.parse(url)
        if path = uri.path
          Micrate::DB.connection_url = url.gsub(path, "/#{uri.scheme}")
          return path.gsub("/", "")
        else
          CLI.logger.puts "Could not determine database name", "ERROR", :red
        end
      end

      private def database_url
        ENV["DATABASE_URL"]? || begin
          CLI.settings.database_url
        end
      end

      private def log(msg)
        CLI.logger.puts msg, "DB", :light_cyan
      end
    end
  end
end
