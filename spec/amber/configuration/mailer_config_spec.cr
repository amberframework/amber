require "../../spec_helper"

module Amber::Configuration
  describe MailerConfig do
    describe "defaults" do
      it "has sensible default values" do
        config = MailerConfig.new
        config.adapter.should eq "memory"
        config.default_from.should eq "noreply@example.com"
        config.smtp.host.should eq "localhost"
        config.smtp.port.should eq 587
        config.smtp.username.should be_nil
        config.smtp.password.should be_nil
        config.smtp.use_tls.should be_true
        config.smtp.helo_domain.should eq "localhost"
      end
    end

    describe "YAML deserialization" do
      it "deserializes from YAML" do
        yaml = <<-YAML
        adapter: "smtp"
        default_from: "app@example.com"
        smtp:
          host: "smtp.example.com"
          port: 465
          username: "user"
          password: "pass"
          use_tls: true
          helo_domain: "example.com"
        YAML

        config = MailerConfig.from_yaml(yaml)
        config.adapter.should eq "smtp"
        config.default_from.should eq "app@example.com"
        config.smtp.host.should eq "smtp.example.com"
        config.smtp.port.should eq 465
        config.smtp.username.should eq "user"
        config.smtp.password.should eq "pass"
        config.smtp.use_tls.should be_true
        config.smtp.helo_domain.should eq "example.com"
      end

      it "deserializes with defaults when smtp section is omitted" do
        yaml = <<-YAML
        adapter: "memory"
        default_from: "test@example.com"
        YAML

        config = MailerConfig.from_yaml(yaml)
        config.adapter.should eq "memory"
        config.smtp.host.should eq "localhost"
        config.smtp.port.should eq 587
      end
    end

    describe "#adapter_symbol" do
      it "returns :memory for memory adapter" do
        config = MailerConfig.new
        config.adapter = "memory"
        config.adapter_symbol.should eq :memory
      end

      it "returns :smtp for smtp adapter" do
        config = MailerConfig.new
        config.adapter = "smtp"
        config.adapter_symbol.should eq :smtp
      end
    end

    describe "#validate!" do
      it "passes for memory adapter" do
        config = MailerConfig.new
        config.adapter = "memory"
        config.validate! # should not raise
      end

      it "passes for smtp adapter with valid config" do
        config = MailerConfig.new
        config.adapter = "smtp"
        config.smtp.host = "smtp.example.com"
        config.smtp.port = 587
        config.validate! # should not raise
      end

      it "raises for smtp adapter with empty host" do
        config = MailerConfig.new
        config.adapter = "smtp"
        config.smtp.host = ""
        expect_raises(Amber::Exceptions::ConfigurationError, /smtp\.host/) do
          config.validate!
        end
      end

      it "raises for smtp adapter with invalid port" do
        config = MailerConfig.new
        config.adapter = "smtp"
        config.smtp.port = 0
        expect_raises(Amber::Exceptions::ConfigurationError, /smtp\.port/) do
          config.validate!
        end
      end
    end
  end

  describe SMTPConfig do
    describe "defaults" do
      it "has sensible defaults" do
        config = SMTPConfig.new
        config.host.should eq "localhost"
        config.port.should eq 587
        config.username.should be_nil
        config.password.should be_nil
        config.use_tls.should be_true
        config.helo_domain.should eq "localhost"
      end
    end
  end
end
