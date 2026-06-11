require "../../spec_helper"

module Amber::Configuration
  describe ServerConfig do
    describe "defaults" do
      it "has sensible default values" do
        config = ServerConfig.new
        config.host.should eq "localhost"
        config.port.should eq 3000
        config.port_reuse.should be_true
        config.process_count.should eq 1
        config.secret_key_base.should eq ""
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        host: "0.0.0.0"
        port: 4000
        port_reuse: false
        process_count: 4
        secret_key_base: "a-very-long-secret-key-that-is-at-least-32-chars"
        ssl:
          key_file: ~
          cert_file: ~
        YAML

        config = ServerConfig.from_yaml(yaml)
        config.host.should eq "0.0.0.0"
        config.port.should eq 4000
        config.port_reuse.should be_false
        config.process_count.should eq 4
        config.secret_key_base.should eq "a-very-long-secret-key-that-is-at-least-32-chars"
      end

      it "deserializes with SSL config" do
        yaml = <<-YAML
        host: "localhost"
        port: 443
        ssl:
          key_file: "/path/to/key.pem"
          cert_file: "/path/to/cert.pem"
        YAML

        config = ServerConfig.from_yaml(yaml)
        config.ssl.key_file.should eq "/path/to/key.pem"
        config.ssl.cert_file.should eq "/path/to/cert.pem"
        config.ssl.is_enabled?.should be_true
      end
    end

    describe "#validate!" do
      it "raises on invalid port" do
        config = ServerConfig.new
        config.port = 0
        expect_raises(Amber::Exceptions::ConfigurationError, /server\.port/) do
          config.validate!
        end
      end

      it "raises on port over 65535" do
        config = ServerConfig.new
        config.port = 70000
        expect_raises(Amber::Exceptions::ConfigurationError, /server\.port/) do
          config.validate!
        end
      end

      it "raises on invalid process_count" do
        config = ServerConfig.new
        config.process_count = 0
        expect_raises(Amber::Exceptions::ConfigurationError, /server\.process_count/) do
          config.validate!
        end
      end

      it "raises on short secret_key_base" do
        config = ServerConfig.new
        config.secret_key_base = "tooshort"
        expect_raises(Amber::Exceptions::ConfigurationError, /secret_key_base/) do
          config.validate!
        end
      end

      it "allows empty secret_key_base in non-production" do
        config = ServerConfig.new
        config.secret_key_base = ""
        config.validate! # should not raise
      end

      it "raises on empty secret_key_base in production" do
        config = ServerConfig.new
        config.secret_key_base = ""
        prod_env = Amber::Environment::Env.new("production")
        expect_raises(Amber::Exceptions::ConfigurationError, /secret_key_base/) do
          config.validate!(prod_env)
        end
      end

      it "passes validation with valid config" do
        config = ServerConfig.new
        config.port = 3000
        config.secret_key_base = "a-very-long-secret-key-that-is-at-least-32-chars"
        config.validate! # should not raise
      end
    end
  end

  describe SSLConfig do
    describe "#is_enabled?" do
      it "returns false when both files are nil" do
        config = SSLConfig.new
        config.is_enabled?.should be_false
      end

      it "returns false when only key_file is set" do
        config = SSLConfig.new
        config.key_file = "/path/to/key.pem"
        config.is_enabled?.should be_false
      end

      it "returns true when both files are set" do
        config = SSLConfig.new
        config.key_file = "/path/to/key.pem"
        config.cert_file = "/path/to/cert.pem"
        config.is_enabled?.should be_true
      end
    end
  end
end
