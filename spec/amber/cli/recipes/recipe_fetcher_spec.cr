require "../../../spec_helper"

module Amber::Recipes
  describe RecipeFetcher do
    context "using a local folder" do
      Spec.before_each do
        Dir.mkdir_p("./mydefault/app")
        Dir.mkdir_p("./mydefault/controller")
        Dir.mkdir_p("./mydefault/model")
        Dir.mkdir_p("./mydefault/scaffold")
      end

      Spec.after_each do
        FileUtils.rm_rf("./mydefault")
      end

      describe "RecipeFetcher" do
        it "should use a local app folder" do
          template = RecipeFetcher.new("app", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/app$/)
        end

        it "should use a local controller folder" do
          template = RecipeFetcher.new("controller", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/controller$/)
        end

        it "should use a local model folder" do
          template = RecipeFetcher.new("model", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/model$/)
        end

        it "should use a local scaffold folder" do
          template = RecipeFetcher.new("scaffold", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/scaffold$/)
        end
      end
    end

    context "using the recipe cache" do
      Spec.before_each do
        Dir.mkdir_p("#{AMBER_RECIPE_FOLDER}/mydefault/app")
        Dir.mkdir_p("#{AMBER_RECIPE_FOLDER}/mydefault/controller")
        Dir.mkdir_p("#{AMBER_RECIPE_FOLDER}/mydefault/model")
        Dir.mkdir_p("#{AMBER_RECIPE_FOLDER}/mydefault/scaffold")
      end

      Spec.after_each do
        FileUtils.rm_rf("#{AMBER_RECIPE_FOLDER}/mydefault")
      end

      describe "RecipeFetcher" do
        it "should use a cached app folder" do
          template = RecipeFetcher.new("app", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/app$/)
        end

        it "should use a cached controller folder" do
          template = RecipeFetcher.new("controller", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/controller$/)
        end

        it "should use a cached model folder" do
          template = RecipeFetcher.new("model", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/model$/)
        end

        it "should use a cached scaffold folder" do
          template = RecipeFetcher.new("scaffold", "mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/scaffold$/)
        end
      end
    end

  end
end
