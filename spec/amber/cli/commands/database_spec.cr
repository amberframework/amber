require "../../../spec_helper"
require "../../../support/helpers/cli_helper"
require "../../../support/fixtures/cli_fixtures"

include CLIHelper
include CLIFixtures

module Amber::CLI
  describe "database" do
    describe "sqlite" do
      cleanup
      scaffold_app(TESTING_APP, "-d", "sqlite")
      db_filename = db_yml("./")["sqlite"]["database"].to_s.sub("sqlite3:", "")

      it "does not create the database when `db create`" do
        MainCommand.run ["db", "create"]
        File.exists?(db_filename).should be_false
      end

      it "does create the database when `db migrate`" do
        MainCommand.run ["generate", "model", "Post"]
        MainCommand.run ["db", "migrate"]
        File.exists?(db_filename).should be_true
        File.stat(db_filename).size.should_not eq 0
      end

      it "deletes the database when `db drop`" do
        MainCommand.run ["db", "drop"]
        File.exists?(db_filename).should be_false
      end
    end
  end
end
