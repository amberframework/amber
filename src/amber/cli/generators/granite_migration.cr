require "./migration"

module Amber::CLI
  class GraniteMigration < Migration
    directory "#{__DIR__}/../templates/migration/granite"
  end
end
