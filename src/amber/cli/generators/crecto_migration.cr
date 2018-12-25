require "./migration"

module Amber::CLI
  class CrectoMigration < Amber::CLI::Migration
    directory "#{__DIR__}/../templates/migration/crecto"
  end
end
