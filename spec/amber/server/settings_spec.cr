require "../../../spec_helper"

describe Amber::Settings do
  it "loads environment settings from test.yml" do
    settings = Amber::Settings.new

    settings.name.should eq "Amber_App"
    settings.port_reuse.should eq true
    settings.redis_url.should eq ""
    settings.database_url.should eq ""
    settings.port.should eq 3000
    settings.process_count.should eq 1
    settings.color.should eq true
    settings.secret_key_base.should_not be_nil
    expected_session = {:key => "amber.session", :store => :signed_cookie, :expires => 0}
    settings.session.should eq expected_session
  end
end
