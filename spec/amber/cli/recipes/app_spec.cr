require "../../../spec_helper"

module Amber::Recipes
  describe App do
    pg_app = App.new("sample-app")
    mysql_app = App.new("sample-app", "mysql")
    sqlite_app = App.new("sample-app", "sqlite")

    describe "#database_name_base" do
      it "should return a postgres compatible name" do
        pg_app.database_name_base.should_not contain "-"
      end

      it "should return a consistent name for all db types" do
        mysql_app.database_name_base.should eq pg_app.database_name_base
        sqlite_app.database_name_base.should eq pg_app.database_name_base
      end
    end

    # a consequence of app initialization is setting the template source folder
    describe "RecipeFetcher" do

      it "should use the default template" do
        recipe_app = App.new("sample-app", "sqlite", "slang", "granite", "default")
        /amber\/src\/(.+)$/ =~ recipe_app.template
        $1.should_not be nil
        $1.should eq "amber/cli/recipes/app/default"
      end

      it "should use a given folder" do
        recipe_app = App.new("sample-app", "sqlite", "slang", "granite", "src/amber/cli/recipes/app/default")
        recipe_app.template.should_not be nil
        recipe_app.template.should eq "src/amber/cli/recipes/app/default"
      end
    end
  end
end
