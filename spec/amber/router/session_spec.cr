require "../../../spec_helper"
include SessionHelper

module Amber::Router
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
