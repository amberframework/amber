require "../../../spec_helper"
require "./migration_spec_helper"

module Amber::CLI
  describe Migration do
    migration = MigrationSpecHelper.sample_migration_for(Migration)

    describe "#create_index_for_reference_fields_sql" do
      it "return the correct CREATE INDEX sql string" do
        expected = MigrationSpecHelper.sample_migration_create_index_sql
        actual = migration.create_index_for_reference_fields_sql
        actual.should eq expected
      end
    end

    context "pg" do
      describe "#create_table_sql" do
        it "should return the correct CREATE TABLE statement" do
          create_table_sql = MigrationSpecHelper.sample_migration_create_table_sql_pg
          migration.create_table_sql.should eq create_table_sql
        end
      end

      describe "#drop_table_sql" do
        it "should return the correct DROP TABLE statement" do
          drop_table_sql = MigrationSpecHelper.sample_migration_drop_table_sql
          migration.drop_table_sql.should eq drop_table_sql
        end
      end
    end
  end
end
