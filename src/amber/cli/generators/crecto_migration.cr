require "./migration"

module Amber::CLI
  class CrectoMigration < Migration
    directory "#{__DIR__}/../templates/migration/crecto"
  end
end
