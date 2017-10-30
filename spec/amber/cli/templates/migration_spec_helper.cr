module Amber::CLI
  module MigrationSpecHelper

    def self.text_for(migration : Migration) : String
      migration.render("./tmp")
      migration_filename = Dir.entries("./tmp/db/migrations").sort.last
      migration_text = File.read("./tmp/db/migrations/#{migration_filename}")
      `rm -rf ./tmp/db`
      return migration_text
    end

  end
end
