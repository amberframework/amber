require "../../spec_helper"
include SessionHelper

module Amber::Router
  Amber.settings.redis_url = ENV["REDIS_URL"] if ENV["REDIS_URL"]?
  describe Session::Store do
    it "creates a cookie session store" do
      session = create_session_config("signed_cookie")
      cookies = new_cookie_store
      store = Session::Store.new(cookies, session)

      store.build.should be_a Session::CookieStore
    end

    it "creates a redis session store" do
      session = create_session_config("redis")
      cookies = new_cookie_store
      store = Session::Store.new(cookies, session)
      store.build.should be_a Session::RedisStore
    end
  end
end
