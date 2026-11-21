require "../../spec_helper"

module Amber::Assets
  describe RenderedTags do
    describe "#fetch" do
      it "renders once and returns the stored tag afterward" do
        tags = RenderedTags.new
        renders = 0
        2.times { tags.fetch(:stylesheet, "stylesheets/app.css") { renders += 1; "<link />" } }

        renders.should eq 1
      end

      it "keeps one path apart for each kind of tag" do
        tags = RenderedTags.new
        tags.fetch(:stylesheet, "app") { "css" }

        tags.fetch(:javascript_include, "app") { "js" }.should eq "js"
      end

      it "stops storing at the entry limit but still renders" do
        tags = RenderedTags.new
        (RenderedTags::ENTRY_LIMIT + 5).times { |index| tags.fetch(:image, "images/#{index}.png") { "tag" } }

        tags.size.should eq RenderedTags::ENTRY_LIMIT
        tags.fetch(:image, "images/beyond.png") { "fresh" }.should eq "fresh"
      end
    end
  end
end
