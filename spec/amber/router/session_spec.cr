require "../../../spec_helper"

module Amber::Router
  describe Session::Store do
    it "creates a cookie session store" do
      cookies = new_cookie_store
      Amber::Server.settings.session = {
        :key     => "name.session",
        :store   => :signed_cookie,
        :expires => 120,
      }

      store = Session::Store.new(cookies)

      store.build.should be_a Session::CookieStore
    end

    it "creates a redis session store" do
      cookies = new_cookie_store
      Amber::Server.settings.session = {
        :key     => "name.session",
        :store   => :redis,
        :expires => 120,
      }

      store = Session::Store.new(cookies)

      store.build.should be_a Session::RedisStore
    end
  end
end
