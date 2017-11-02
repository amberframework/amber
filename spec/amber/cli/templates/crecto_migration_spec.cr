require "../../../spec_helper"
require "./migration_spec_helper"

module Amber::CLI
  describe CrectoMigration do
    describe "#render" do
      context "when rendering a migration with an index for belongs_to" do
        migration = MigrationSpecHelper.sample_migration_for(CrectoMigration)
        migration_text = MigrationSpecHelper.text_for(migration)

        it "create the index with proper naming convention" do
          create_index_sql = MigrationSpecHelper.sample_migration_create_index_sql
          migration_text.should contain create_index_sql
        end
      end

      context "pg" do
        migration = MigrationSpecHelper.sample_migration_for(GraniteMigration)
        migration_text = MigrationSpecHelper.text_for(migration)

        it "should contain correct CREATE TABLE statement" do
          create_table_sql = MigrationSpecHelper.sample_migration_create_table_sql_pg
          migration_text.should contain create_table_sql
        end

        it "should contain correct CREATE INDEX statement" do
          create_index_sql = MigrationSpecHelper.sample_migration_create_index_sql
          migration_text.should contain create_index_sql
        end

        it "should contain correct DROP TABLE statement" do
          drop_table_sql = MigrationSpecHelper.sample_migration_drop_table_sql
          migration_text.should contain drop_table_sql
        end
      end
    end
  end
end
