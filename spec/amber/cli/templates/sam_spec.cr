require "../../../spec_helper"

module Amber::CLI
  module SamSpecHelper
    def self.text_for(sam : Sam) : String
      sam.render("./tmp/app")
      File.read("./tmp/app/sam.cr")
    ensure
      `rm -rf ./tmp/app`
    end
  end

  describe Sam do
    describe "#render" do
      context "with jennifer model" do
        sam = Amber::CLI::Sam.new("jennifer")
        file = SamSpecHelper.text_for(sam)

        it { file.should contain("Sam.help") }
        it { file.should contain(%(require "./db/migrations/*")) }
        it { file.should contain(%(load_dependencies "jennifer")) }
      end
    end
  end
end
