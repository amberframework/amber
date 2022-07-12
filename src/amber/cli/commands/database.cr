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

          TIP: If you're using ZSH and trying to pass model params that are nilable, wrap those arguments in quotes.

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

      # ameba:disable Metrics/CyclomaticComplexity
      def run
        CLI.toggle_colors(options.no_color?)
        params = ""
        commands = args.commands

        if commands.first.matches?(/migration|rollback|model|step/)
          new_commands = [commands.delete_at(0)]
          params = commands.join(" ")
          commands = new_commands
        end

        commands.each do |command|
          case command
          when "create"
            puts `crystal sam.cr db:create`
          when "drop"
            puts `crystal sam.cr db:drop`
          when "migration"
            puts `crystal sam.cr generate:migration #{params}`
          when "model"
            puts `crystal sam.cr generate:model #{params}`
          when "migrate"
            puts `crystal sam.cr db:migrate`
          when "rollback"
            puts `crystal sam.cr db:rollback #{params}`
          when "schema_load"
            puts `crystal sam.cr db:schema:load`
          when "seed"
            puts `crystal sam.cr db:seed`
          when "setup"
            puts `crystal sam.cr db:create && crystal sam.cr db:schema:load`
          when "step"
            puts `crystal sam.cr db:step #{params}`
          when "version"
            puts `crystal sam.cr db:version`
          else
            exit! help: true, error: false
          end
        end
      end

    end
  end
end
