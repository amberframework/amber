require "../../../spec_helper"

module Amber::Plugins
  describe Plugin do
    describe "#can_generate?" do
      Spec.before_each do
        Dir.mkdir_p(".plugins/lib/test/plugin")
      end

      Spec.after_each do
        FileUtils.rm_rf(".plugins")
      end

      it "should return true for amberplugin/test" do
        Plugin.can_generate?("amberplugin/test").should eq true
      end

      it "should return true for test" do
        Plugin.can_generate?("test").should eq true
      end
    end
  end
end
