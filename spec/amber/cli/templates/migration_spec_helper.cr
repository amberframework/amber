module Amber::CLI
  module MigrationSpecHelper

    def self.text_for(migration : Migration) : String
      migration_text = ""
      begin
        migration.render("./tmp")
        migration_filename = Dir.entries("./tmp/db/migrations").sort.last
        migration_text = File.read("./tmp/db/migrations/#{migration_filename}")
      ensure
        `rm -rf ./tmp/db`
      end
      return migration_text
    end

    def self.sample_migration_for(migration_template_type)
      migration_template_type.new("post", ["user:ref", "title:string", "body:text"])
    end

    def self.sample_migration_migrate_up_text_pg
      <<-SQL
      CREATE TABLE posts (
        id BIGSERIAL PRIMARY KEY,
        user_id BIGINT,
        title VARCHAR,
        body TEXT,
        created_at TIMESTAMP,
        updated_at TIMESTAMP
      );
      SQL
    end

    def self.sample_migration_migrate_down_text_pg
      "DROP TABLE IF EXISTS posts;"
    end

  end
end
