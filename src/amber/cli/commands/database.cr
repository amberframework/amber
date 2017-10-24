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
      end

      class Help
        caption "# Performs database maintenance tasks"
      end

      def run
        args.commands.each do |command|
          Micrate::Cli.setup_logger
          Micrate::DB.connection_url = database_url
          begin
            case command
            when "drop"
              drop_database
            when "create"
              create_database
            when "seed"
              `crystal db/seeds.cr`
              puts "Seeded database"
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
      end

      def drop_database
        name = set_database_to_schema
        Micrate::DB.connect do |db|
          db.exec "DROP DATABASE #{name};"
        end
        puts "Dropped database #{name}"
      end

      def create_database
        name = set_database_to_schema
        Micrate::DB.connect do |db|
          db.exec "CREATE DATABASE #{name};"
        end
        puts "Created database #{name}"
      end

      def set_database_to_schema
        url = Micrate::DB.connection_url.to_s
        uri = URI.parse(url)
        if path = uri.path
          Micrate::DB.connection_url = url.gsub(path, "/#{uri.scheme}")
          return path.gsub("/", "")
        else
          raise "could not determine database name"
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

      private def env(url)
        regex = /\$\{(.*?)\}/
        if regex.match(url)
          url = url.gsub(regex) do |match|
            ENV[match.gsub("${", "").gsub("}", "")]
          end
        else
          return url
        end
      end
    end
  end
end
