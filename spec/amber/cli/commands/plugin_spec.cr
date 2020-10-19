require "../../../spec_helper"

module Amber::Plugins
  describe Plugin do
    describe "#can_generate?" do
      Spec.before_each do
        Dir.mkdir_p("#{Dir.current}/lib/test/plugin")
      end

      Spec.after_each do
        FileUtils.rm_rf("#{Dir.current}/lib/test/plugin")
      end

      it "should return true for test" do
        Plugin.can_generate?("test").should eq true
      end
    end
  end
end
