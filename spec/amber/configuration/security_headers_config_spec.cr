require "../../spec_helper"

module Amber::Configuration
  describe SecurityHeadersConfig do
    describe "defaults" do
      it "has secure default values" do
        config = SecurityHeadersConfig.new
        config.content_type_options.should eq "nosniff"
        config.frame_options.should eq "DENY"
        config.content_security_policy.should eq "frame-ancestors 'none'"
        config.referrer_policy.should eq "strict-origin-when-cross-origin"
      end

      it "pins only this host with HSTS, leaving sibling subdomains alone" do
        SecurityHeadersConfig.new.strict_transport_security.should eq "max-age=63072000"
      end

      it "leaves the feature-disabling and popup-severing headers off" do
        config = SecurityHeadersConfig.new
        config.permissions_policy.should eq ""
        config.cross_origin_opener_policy.should eq ""
        config.list_of_headers.map(&.first).should_not contain "Permissions-Policy"
        config.list_of_headers.map(&.first).should_not contain "Cross-Origin-Opener-Policy"
      end

      it "is present on a new AppConfig" do
        AppConfig.new.security_headers.frame_options.should eq "DENY"
      end
    end

    describe "YAML deserialization" do
      it "raises for a misspelled key instead of keeping that header's default" do
        expect_raises(YAML::ParseException, /content_security_polcy/) do
          SecurityHeadersConfig.from_yaml(%(content_security_polcy: "default-src 'self'"))
        end
      end

      it "overrides only the keys the YAML names" do
        yaml = <<-YAML
          frame_options: "SAMEORIGIN"
          referrer_policy: "no-referrer"
          YAML

        config = SecurityHeadersConfig.from_yaml(yaml)
        config.frame_options.should eq "SAMEORIGIN"
        config.referrer_policy.should eq "no-referrer"
        config.content_type_options.should eq "nosniff"
      end
    end

    describe "#list_of_headers" do
      it "pairs each always-sent header with its value" do
        list_of_headers = SecurityHeadersConfig.new.list_of_headers
        list_of_headers.map(&.first).should eq [
          "X-Content-Type-Options",
          "X-Frame-Options",
          "Content-Security-Policy",
          "Referrer-Policy",
        ]
      end

      it "leaves out a header whose value is empty" do
        config = SecurityHeadersConfig.new
        config.frame_options = ""
        config.list_of_headers.map(&.first).should_not contain "X-Frame-Options"
      end

      it "never includes Strict-Transport-Security" do
        SecurityHeadersConfig.new.list_of_headers.map(&.first).should_not contain "Strict-Transport-Security"
      end
    end

    describe "#sends_strict_transport_security?" do
      it "is true by default and false when the value is empty" do
        config = SecurityHeadersConfig.new
        config.sends_strict_transport_security?.should be_true
        config.strict_transport_security = ""
        config.sends_strict_transport_security?.should be_false
      end
    end

    describe "#validate!" do
      it "passes for the defaults" do
        SecurityHeadersConfig.new.validate!
      end

      it "is part of AppConfig#validate!" do
        config = AppConfig.new
        config.server.secret_key_base = "a" * 64
        config.validate!
      end
    end

    describe "assigning a value" do
      it "raises for a value containing a line break and keeps the old value" do
        config = SecurityHeadersConfig.new
        expect_raises(Amber::Exceptions::ConfigurationError, /security_headers\.referrer_policy/) do
          config.referrer_policy = "no-referrer\r\nSet-Cookie: injected=1"
        end
        config.referrer_policy.should eq "strict-origin-when-cross-origin"
      end

      it "raises for NUL, DEL and other control characters that HTTP headers refuse" do
        ["DENY\u0000", "DENY\u007F", "DENY\u0001"].each do |value|
          config = SecurityHeadersConfig.new
          expect_raises(Amber::Exceptions::ConfigurationError, /security_headers\.frame_options/) do
            config.frame_options = value
          end
        end
      end

      it "accepts a tab, as HTTP headers do" do
        config = SecurityHeadersConfig.new
        config.permissions_policy = "camera=(),\tmicrophone=()"
        config.permissions_policy.should eq "camera=(),\tmicrophone=()"
      end
    end

    describe "YAML loading" do
      it "raises for a control character while loading" do
        expect_raises(Amber::Exceptions::ConfigurationError, /security_headers\.frame_options/) do
          SecurityHeadersConfig.from_yaml(%(frame_options: "DENY\\x01"))
        end
      end
    end
  end
end
