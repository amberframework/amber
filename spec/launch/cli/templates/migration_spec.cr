require "../../../spec_helper"
require "./migration_spec_helper"

module Launch::CLI
  describe Migration do
    describe "#render" do
      context "when rendering a migration with a reference" do
        migration = MigrationSpecHelper.sample_migration_for(Migration)
        migration_text = MigrationSpecHelper.text_for(migration)

        it "can generate a proper migration" do
          sample_migration = MigrationSpecHelper.sample_migration_create_table
          migration_text.should contain sample_migration
        end
      end
    end
  end
end
