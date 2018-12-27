require "../../../spec_helper"

module Amber::CLI
  describe App do
    pg_app = App.new("sample-app")
    mysql_app = App.new("sample-app", "mysql")
    sqlite_app = App.new("sample-app", "sqlite")

    describe "#database_name" do
      it "should return a postgres compatible name" do
        pg_app.database_name.should_not contain "-"
      end

      it "should return a consistent name for all db types" do
        mysql_app.database_name.should eq pg_app.database_name
        sqlite_app.database_name.should eq pg_app.database_name
      end
    end
  end
end
