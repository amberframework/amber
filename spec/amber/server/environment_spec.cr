require "../../../spec_helper"

describe Amber::Server do
  describe "environment" do
    it "loads expected output" do
      expected = <<-EXP
      @@name = "amber_test_app"
      @@port_reuse = true
      @@log = ::Logger.new(STDOUT)
      @@log.level = ::Logger::INFO
      @@process_count = 1
      @@redis_url = "\#{ENV[%(REDIS_URL)]? || %(redis://localhost:6379)}"
      @@port = 3000
      @@host = "0.0.0.0"
      @@secret_key_base = "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
      @@session = {:key => "amber.session", :store => "signed_cookie", :expires => "0"}
      class_getter secrets = {"description": "Store your test secrets credentials and settings here.", "database": "mysql://root@localhost:3306/amber_test_app_test"}

      EXP
      {{run("../../../src/amber/server/environment.cr").stringify}}.should eq expected

    end
  end
end
