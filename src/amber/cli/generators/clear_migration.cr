require "./migration"

module Amber::CLI
  class ClearMigration < Migration
    directory "#{__DIR__}/../templates/migration/clear"
  end
end
