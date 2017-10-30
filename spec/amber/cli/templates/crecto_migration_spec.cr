require "../../../spec_helper"
require "./migration_spec_helper"

module Amber::CLI
  describe CrectoMigration do
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
    end
  end
end
