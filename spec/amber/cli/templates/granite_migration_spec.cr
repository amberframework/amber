require "../../../spec_helper"
require "./migration_spec_helper"

module Amber::CLI
  describe GraniteMigration do
    describe "#render" do
      context "when rendering a migration with an index for belongs_to" do
        migration = GraniteMigration.new("post", ["user:ref", "title:string"])
        migration_text = MigrationSpecHelper.text_for(migration)

        it "create the index with proper naming convention" do
          create_index_line = <<-SQL
            CREATE INDEX post_user_id_idx ON posts (user_id)
            SQL
          migration_text.should contain create_index_line
        end

      end

      context "pg" do
        migration = MigrationSpecHelper.sample_migration_for(GraniteMigration)
        migration_text = MigrationSpecHelper.text_for(migration)
        migrate_up_text = MigrationSpecHelper.sample_migration_migrate_up_text_pg
        migrate_down_text = MigrationSpecHelper.sample_migration_migrate_down_text_pg

        it "should contain correct CREATE TABLE statement" do
          migration_text.should contain migrate_up_text
        end

        it "should contain correct DROP TABLE statement" do
          migration_text.should contain migrate_down_text
        end
      end
      
    end
  end
end
