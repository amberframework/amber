require "../../spec_helper"

module Amber::Configuration
  describe DatabaseConfig do
    describe "defaults" do
      it "has empty URL by default" do
        config = DatabaseConfig.new
        config.url.should eq ""
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        url: "postgres://localhost:5432/myapp_dev"
        YAML

        config = DatabaseConfig.from_yaml(yaml)
        config.url.should eq "postgres://localhost:5432/myapp_dev"
      end
    end
  end
end
