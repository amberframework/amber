require "../../../spec_helper"

describe Amber::Environment do
  it "loads test environment settings" do
    env = "test"
    path = "./spec/support/config"
    settings = Amber::Environment.load(path, env)

    settings.name.should eq "amber_test_app"
    settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
    settings.port.should eq 4000
    settings.port_reuse.should be_true
    settings.host.should eq "0.0.0.0"
    settings.process_count.should eq 16
    settings.ssl_key_file.should eq "some key file"
    settings.ssl_cert_file.should eq "some cert file"
    settings.redis_url.should eq "redis://localhost:6379"
    settings.session["key"].should eq "myapp.session"
    settings.session["store"].should eq "encrypted_cookie"
    settings.session["expires"].should eq 10
    settings.secrets.empty?.should be_false
    settings.secrets["database"].should eq "mysql://root@localhost:3306/amber_test_app_test"
  end

  it "load default settings when environment when keys don't exist" do
    env = "empty"
    path = "./spec/support/config"
    settings = Amber::Environment.load(path, env)

    settings.name.should eq "Empty_Config"
    settings.secret_key_base.empty?.should be_false
    settings.port.should eq 3000
    settings.port_reuse.should be_true
    settings.host.should eq "localhost"
    settings.process_count.should eq 1
    settings.ssl_key_file.should be_nil
    settings.ssl_cert_file.should be_nil
    settings.redis_url.should be_nil
    settings.session["key"].should eq "amber.session"
    settings.session["store"].should eq "signed_cookie"
    settings.session["expires"].should eq 0
    settings.secrets.empty?.should be_true
  end

  it "raises an error when environment file does not exist" do
    env = "bad_file"
    path = "./spec/support/config"

    expect_raises do
      Amber::Environment.load(path, env)
    end
  end
end
