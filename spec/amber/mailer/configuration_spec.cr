require "../../spec_helper"

describe Amber::Mailer::Configuration do
  before_each do
    Amber::Mailer::Configuration.reset
  end

  describe "#initialize" do
    it "has sensible default values" do
      config = Amber::Mailer::Configuration.instance
      config.adapter.should eq(:memory)
      config.smtp_host.should eq("localhost")
      config.smtp_port.should eq(587)
      config.smtp_username.should be_nil
      config.smtp_password.should be_nil
      config.use_tls.should be_true
      config.default_from.should eq("noreply@example.com")
      config.helo_domain.should eq("localhost")
    end
  end

  describe ".instance" do
    it "returns the same instance on repeated calls" do
      a = Amber::Mailer::Configuration.instance
      b = Amber::Mailer::Configuration.instance
      a.should be(b)
    end
  end

  describe ".configure" do
    it "yields the singleton instance for modification" do
      Amber::Mailer::Configuration.configure do |config|
        config.adapter = :smtp
        config.smtp_host = "mail.example.com"
        config.smtp_port = 465
        config.smtp_username = "user"
        config.smtp_password = "pass"
        config.use_tls = false
        config.default_from = "hello@example.com"
        config.helo_domain = "example.com"
      end

      config = Amber::Mailer::Configuration.instance
      config.adapter.should eq(:smtp)
      config.smtp_host.should eq("mail.example.com")
      config.smtp_port.should eq(465)
      config.smtp_username.should eq("user")
      config.smtp_password.should eq("pass")
      config.use_tls.should be_false
      config.default_from.should eq("hello@example.com")
      config.helo_domain.should eq("example.com")
    end
  end

  describe ".reset" do
    it "resets configuration to defaults" do
      Amber::Mailer::Configuration.configure do |config|
        config.adapter = :smtp
        config.smtp_host = "custom.host"
      end

      Amber::Mailer::Configuration.reset

      config = Amber::Mailer::Configuration.instance
      config.adapter.should eq(:memory)
      config.smtp_host.should eq("localhost")
    end
  end

  describe "#build_adapter" do
    it "builds a MemoryAdapter for :memory" do
      config = Amber::Mailer::Configuration.instance
      config.adapter = :memory

      adapter = config.build_adapter
      adapter.should be_a(Amber::Mailer::MemoryAdapter)
    end

    it "builds an SMTPAdapter for :smtp" do
      config = Amber::Mailer::Configuration.instance
      config.adapter = :smtp
      config.smtp_host = "smtp.example.com"
      config.smtp_port = 587
      config.smtp_username = "user"
      config.smtp_password = "pass"
      config.use_tls = true
      config.helo_domain = "example.com"

      adapter = config.build_adapter
      adapter.should be_a(Amber::Mailer::SMTPAdapter)

      smtp = adapter.as(Amber::Mailer::SMTPAdapter)
      smtp.host.should eq("smtp.example.com")
      smtp.port.should eq(587)
      smtp.username.should eq("user")
      smtp.password.should eq("pass")
      smtp.use_tls.should be_true
      smtp.helo_domain.should eq("example.com")
    end

    it "raises ArgumentError for unknown adapter" do
      config = Amber::Mailer::Configuration.instance
      config.adapter = :unknown

      expect_raises(ArgumentError, "Unknown mailer adapter: unknown") do
        config.build_adapter
      end
    end
  end
end
