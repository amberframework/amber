require "../../spec_helper"

module Amber::Configuration
  describe StaticConfig do
    describe "defaults" do
      it "has empty headers by default" do
        config = StaticConfig.new
        config.headers.should eq({} of String => String)
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        headers:
          Cache-Control: "private, max-age=7200"
          X-Custom: "value"
        YAML

        config = StaticConfig.from_yaml(yaml)
        config.headers.should eq({"Cache-Control" => "private, max-age=7200", "X-Custom" => "value"})
      end
    end
  end
end
