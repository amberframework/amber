require "../../../spec_helper"

module Amber::Plugins
  describe PluginFetcher do
    context "using a local folder" do
      Spec.before_each do
        Dir.mkdir_p("./myplugin/test/plugin")
      end

      Spec.after_each do
        FileUtils.rm_rf("./myplugin")
      end

      describe "PluginFetcher" do
        it "should use a local plugin folder" do
          template = PluginFetcher.new("./myplugin/test").fetch
          template.should_not be nil
          template.should match(/.+myplugin\/test\/plugin$/)
        end
      end
    end

    context "from a github shard" do
      Spec.before_each do
        Dir.mkdir_p(".plugins/lib")
      end

      Spec.after_each do
        FileUtils.rm_rf(".plugins")
      end

      describe "PluginFetcher" do
        it "should use a shard app folder" do
          template = PluginFetcher.new("amberplugin/authorize").fetch
          template.should_not be nil
          template.should match(/.plugins\/lib\/authorize\/plugin$/)
        end
      end
    end

    context "using a short shard name" do
      Spec.before_each do
        Dir.mkdir_p(".plugins/lib")
      end

      Spec.after_each do
        FileUtils.rm_rf(".plugins")
      end

      describe "PluginFetcher" do
        it "should use a shard name" do
          template = PluginFetcher.new("authorize").fetch
          template.should_not be nil
          template.should match(/.plugins\/lib\/authorize\/plugin$/)
        end
      end
    end
  end
end
