require "../../../spec_helper"

module Amber::Recipes
  describe Recipe do
    recipe = "mydefault"

    describe "#can_generate?" do
      Spec.before_each do
        Dir.mkdir_p("./mydefault/app")
        Dir.mkdir_p("./mydefault/controller")
        Dir.mkdir_p("./mydefault/model")
        Dir.mkdir_p("./mydefault/scaffold")
      end

      Spec.after_each do
        FileUtils.rm_rf("./mydefault")
      end

      it "should return true for controller" do
        Recipe.can_generate?("controller", recipe).should eq true
      end

      it "should return true for model" do
        Recipe.can_generate?("model", recipe).should eq true
      end

      it "should return true for scaffold" do
        Recipe.can_generate?("scaffold", recipe).should eq true
      end
    end
  end
end
