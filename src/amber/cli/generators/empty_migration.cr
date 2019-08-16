require "./migration"

module Amber::CLI
  class EmptyMigration < Migration
    command :migration
    directory "#{__DIR__}/../templates/migration/empty"
  end
end
