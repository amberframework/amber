require "../../../spec_helper"

module Amber::Recipes
  describe Recipe do
    pg_app = App.new("sample-app")
    mysql_app = App.new("sample-app", "mysql")
    sqlite_app = App.new("sample-app", "sqlite")

    recipe = "mydefault"

    describe "#can_generate?" do
      Spec.before_each do
        Dir.mkdir_p("./mydefault/app")
        Dir.mkdir_p("./mydefault/controller")
      end

      Spec.after_each do
        FileUtils.rm_rf("./mydefault")
      end

      it "should return true for default app" do
        Recipe.can_generate?("app", recipe).should eq true
      end

      it "should return true for default controller" do
        Recipe.can_generate?("controller", recipe).should eq true
      end

    end

  end
end
