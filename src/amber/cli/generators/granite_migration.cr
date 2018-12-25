require "./migration"

module Amber::CLI
  class GraniteMigration < Amber::CLI::Migration
    directory "#{__DIR__}/../templates/migration/granite"
  end
end
