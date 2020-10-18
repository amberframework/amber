require "../../../spec_helper"
require "./migration_spec_helper"

module Launch::CLI
  describe EmptyMigration do
    migration = MigrationSpecHelper.sample_migration_for(Migration)

    # TODO: Is this needed? Can we get rid of this file?
    # describe "#create_index_for_reference_fields_sql" do
    #   it "return the correct CREATE INDEX sql string" do
    #     expected = MigrationSpecHelper.sample_migration_create_index_sql
    #     actual = migration.create_index_for_reference_fields_sql
    #     actual.should eq expected
    #   end
    # end
  end
end
