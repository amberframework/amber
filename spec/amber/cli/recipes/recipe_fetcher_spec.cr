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

    context "app from a github shard" do
      Spec.before_each do
        Dir.mkdir_p("./mydefault")
      end

      Spec.after_each do
        FileUtils.rm_rf("./mydefault")
      end

      describe "RecipeFetcher" do
        it "should use a shard app folder" do
          template = RecipeFetcher.new("app", "damianham/amber_granite", "./mydefault").fetch
          template.should_not be nil
          template.should match(/.+mydefault\/.recipes\/lib\/amber_granite\/app$/)
        end
      end
    end

    context "using a github shard" do
      describe "RecipeFetcher" do
        Dir.mkdir_p("./myapp")
        RecipeFetcher.new("app", "damianham/amber_granite", "./myapp").fetch

        it "should use a shard controller folder" do
          Dir.cd("./myapp") do
            template = RecipeFetcher.new("controller", "damianham/amber_granite").fetch
            template.should_not be nil
            template.should match(/.+\.recipes\/lib\/amber_granite\/controller$/)
          end
        end

        it "should use a shard model folder" do
          Dir.cd("./myapp") do
            template = RecipeFetcher.new("model", "damianham/amber_granite").fetch
            template.should_not be nil
            template.should match(/.+\.recipes\/lib\/amber_granite\/model$/)
          end
        end

        it "should use a shard scaffold folder" do
          Dir.cd("./myapp") do
            template = RecipeFetcher.new("scaffold", "damianham/amber_granite").fetch
            template.should_not be nil
            template.should match(/.+\.recipes\/lib\/amber_granite\/scaffold$/)
          end
        end

        FileUtils.rm_rf("./myapp")
      end
    end
  end
end
