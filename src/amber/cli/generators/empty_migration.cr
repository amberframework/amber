require "./migration"

module Launch::CLI
  class EmptyMigration < Migration
    command :migration
    directory "#{__DIR__}/../templates/migration/empty"
  end
end
