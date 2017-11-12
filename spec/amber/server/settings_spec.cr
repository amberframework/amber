require "../../../spec_helper"

describe Amber::Settings do
  it "loads environment settings from test.yml" do
    settings = Amber::Settings.new

    settings.name.should eq "amber_test_app"
    settings.port_reuse.should eq true
    settings.redis_url.should eq "#{ENV["REDIS_URL"]? || "redis://localhost:6379"}"
    settings.port.should eq 3000
    settings.color.should eq true
    settings.secret_key_base.should eq "mV6kTmG3k1yVFh-fPYpugSn0wbZveDvrvfQuv88DPF8"
    expected_session = {:key => "amber.session", :store => :signed_cookie, :expires => 0}
    settings.session.should eq expected_session
    expected_secrets = {
      description: "Store your test secrets credentials and settings here.",
      database:    "mysql://root@localhost:3306/amber_test_app_test",
    }
    settings.secrets.should eq expected_secrets
  end

  it "loads environment settings from test.yml with env overload for port." do
    ENV["PORT"] = "1337"
    settings = Amber::Settings.new

    settings.port.should eq 1337
  end
end
