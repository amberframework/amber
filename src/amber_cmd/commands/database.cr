require "micrate"
require "pg"
require "mysql"
require "sqlite3"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "db", aliased: "database"

    class Database < Cli::Command
      command_name "database"

      class Options
        arg_array "commands", desc: "drop create migrate rollback redo status version seed"
      end

      class Help
        caption "# Performs database maintenance tasks"
      end

      def run
        Micrate::Cli.setup_logger
        Micrate::DB.connection_url = database_url
        args.commands.each do |command|
          begin
            case command
            when "create"
              uri = URI.parse(database_url)
              if name = uri.path
                name = name.gsub("/", "")
                Micrate::DB.connection_url = database_url.gsub(name, uri.scheme)
                create_database(name)
                puts "Created database #{name}"
              end
            when "drop"
              uri = URI.parse(database_url)
              if name = uri.path
                name = name.gsub("/", "")
                drop_database(name)
                puts "Dropped database #{name}"
              end
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

      private def drop_database(name)
        Micrate::DB.connect do |db|
          db.exec "DROP DATABASE #{name};"
        end
      end

      private def create_database(name)
        Micrate::DB.connect do |db|
          db.exec "CREATE DATABASE #{name};"
        end
      end
    end
  end
end

