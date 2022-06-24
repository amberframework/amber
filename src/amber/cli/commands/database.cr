module Amber::CLI
  Log = ::Log.for("database")

  class MainCommand < ::Cli::Supercommand
    command "db", aliased: "database"

    class Database < Command
      command_name "database"

      class Options
        arg_array "commands", desc: "create drop migrate migration model rollback schema_load seed setup step version"
        bool "--no-color", desc: "disable colored output", default: false
        help
      end

      class Help
        header <<-EOS
          Performs database migrations and maintenance tasks. Powered by Jennifer (https://github.com/imdrasil/jennifer.cr)

        Commands:
          create        Will create only one database. This means that for test environment (and for any extra environment you want) this command should be invoked separately.
          drop          Drops database described in the configuration.
          migration     Generates simple migration template.
          model         Generates model and related migration based on the given definition. generate:model Article title:string text:text? author:reference
          migrate       Runs all pending migrations and stores them in the versions table. After execution of new migrations database schema is dumped to the structure.sql file.
          rollback      Rollbacks the last run migration. Pass in a number as the final argument to rollback that number of migrations. Use `-v <migration_number>` to rollback to a specific migration version.
          schema_load   Creates database from the structure.sql file.
          seed          Populates database with seeds. By default this task is empty and should be defined per project bases.
          setup         Creates database, invokes all pending migrations and populate database with seeds.
          step          Runs exact count of migrations (1 by default). `amber db:step <count>` where <count> is an optional integer
          version       Outputs current database version.
        EOS
        caption "performs database migrations, model generations and maintenance tasks"
      end

      def run
        CLI.toggle_colors(options.no_color?)
        #connect_to_database if args.commands.empty?
        puts "You ran the DB command! YAY!"
        puts args
        process_commands(args.commands)
      #rescue e : DB::ConnectionRefused
      #  exit! "Connection unsuccessful: #{Micrate::DB.connection_url.colorize(:light_blue)}", error: true
      #rescue e : Exception
      #  exit! e.message, error: true
      end

      private def process_commands(commands)
        commands.each do |command|
          case command
          when "create"
            `crystal sam.cr -- db:create`
          when "drop"
            `crystal sam.cr -- db:drop`
          when "migration"
            `crystal sam.cr -- db:migration`
          when "model"
            # This should have args passed in
            `crystal sam.cr -- db:model`
          when "migrate"
            `crystal sam.cr -- db:migrate`
          when "rollback"
            # This should have args passed in
            `crystal sam.cr -- db:rollback`
          when "schema_load"
            # This should have args passed in
            `crystal sam.cr -- db:rollback`
          when "seed"
            `crystal sam.cr -- db:seed`
          when "setup"
            `crystal sam.cr -- db:seed`
          when "step"
            `crystal sam.cr -- db:step`
          when "version"
            `crystal sam.cr -- db:version`
          else
            exit! help: true, error: false
          end
        end
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

      # private def database_url
      #   ENV["DATABASE_URL"]? || CLI.settings.database_url
      # end
    end
  end
end
