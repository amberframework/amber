require "../../../spec_helper"

module Amber::CLI
  describe App do
    pg_app = App.new("sample-app", "pg", "slang", "jennifer", false)
    mysql_app = App.new("sample-app", "mysql", "slang", "jennifer", false)
    sqlite_app = App.new("sample-app", "sqlite", "slang", "jennifer", false)

    describe "#database_name_base" do
      it "should return a postgres compatible name" do
        pg_app.database_name_base.should_not contain "-"
      end

      it { mysql_app.database_name_base.should eq pg_app.database_name_base }
      it { sqlite_app.database_name_base.should eq pg_app.database_name_base }
    end
  end
end
