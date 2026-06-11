require "../../spec_helper"

module Amber::Configuration
  describe SessionConfig do
    describe "defaults" do
      it "has sensible default values" do
        config = SessionConfig.new
        config.key.should eq "amber.session"
        config.store.should eq "signed_cookie"
        config.expires.should eq 0
        config.adapter.should eq "memory"
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        key: "myapp.session"
        store: "encrypted_cookie"
        expires: 3600
        adapter: "redis"
        YAML

        config = SessionConfig.from_yaml(yaml)
        config.key.should eq "myapp.session"
        config.store.should eq "encrypted_cookie"
        config.expires.should eq 3600
        config.adapter.should eq "redis"
      end
    end

    describe "#store_type" do
      it "returns :signed_cookie for signed_cookie" do
        config = SessionConfig.new
        config.store = "signed_cookie"
        config.store_type.should eq :signed_cookie
      end

      it "returns :encrypted_cookie for encrypted_cookie" do
        config = SessionConfig.new
        config.store = "encrypted_cookie"
        config.store_type.should eq :encrypted_cookie
      end

      it "returns :redis for redis" do
        config = SessionConfig.new
        config.store = "redis"
        config.store_type.should eq :redis
      end

      it "returns :encrypted_cookie for unknown store type" do
        config = SessionConfig.new
        config.store = "unknown"
        config.store_type.should eq :encrypted_cookie
      end
    end

    describe "#validate!" do
      it "passes for valid store types" do
        config = SessionConfig.new
        config.store = "signed_cookie"
        config.validate! # should not raise
      end

      it "raises for invalid store type" do
        config = SessionConfig.new
        config.store = "invalid_store"
        expect_raises(Amber::Exceptions::ConfigurationError, /session\.store/) do
          config.validate!
        end
      end
    end
  end
end
