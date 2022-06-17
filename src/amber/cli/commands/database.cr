module Amber::CLI
  Log = ::Log.for("database")

  class MainCommand < ::Cli::Supercommand
    command "db", aliased: "database"

    class Database < Command
      command_name "database"

      class Options
        arg_array "commands", desc: "drop create migrate rollback redo status version seed"
        bool "--no-color", desc: "disable colored output", default: false
        help
      end

      class Help
        header <<-EOS
          Performs database migrations and maintenance tasks. Powered by micrate (https://github.com/juanedi/micrate)

        Commands:
          drop      drops the database
          create    creates the database
          migrate   migrate the database to the most recent version available
          rollback  roll back the database version by 1
          redo      re-run the latest database migration
          status    dump the migration status for the current database
          version   print the current version of the database
          seed      initialize the database with seed data
        EOS
        caption "performs database migrations and maintenance tasks"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        #connect_to_database if args.commands.empty?

      #  process_commands(args.commands)
      #rescue e : DB::ConnectionRefused
      #  exit! "Connection unsuccessful: #{Micrate::DB.connection_url.colorize(:light_blue)}", error: true
      #rescue e : Exception
      #  exit! e.message, error: true
      end

      # private def process_commands(commands)
      #   commands.each do |command|
      #     Micrate::DB.connection_url = database_url
      #     case command
      #     when "drop"
      #       drop_database
      #     when "create"
      #       create_database
      #     when "seed"
      #       Helpers.run("crystal db/seeds.cr", wait: true, shell: true)
      #       info "Seeded database"
      #     when "migrate"
      #       migrate
      #     when "rollback"
      #       Micrate::Cli.run_down
      #     when "redo"
      #       Micrate::Cli.run_redo
      #     when "status"
      #       Micrate::Cli.run_status
      #     when "version"
      #       Micrate::Cli.run_dbversion
      #     when "connect"
      #       connect_to_database
      #     else
      #       exit! help: true, error: false
      #     end
      #   end
      # end


      # private def command_line_tool
      #   case Amber::CLI.config.database
      #   when "pg"
      #     "psql"
      #   when "mysql"
      #     "mysql"
      #   when "sqlite"
      #     "sqlite3"
      #   else
      #     exit! "invalid database configuration", error: true
      #   end
      # end

      # private def database_url
      #   ENV["DATABASE_URL"]? || CLI.settings.database_url
      # end
    end
  end
end
