require "../../../spec_helper"

module Amber::Router
  describe SessionFactory do
    it "creates a cookie session store" do
      cookies = new_cookie_store
      Amber::Server.instance.session = {
        :key     => "name.session",
        :store   => :cookie,
        :expires => 120,
        :secret  => "secret",
      }

      store = SessionFactory.new(cookies)

      store.build.should be_a Session::CookieStore
    end

    it "creates a redis session store" do
      cookies = new_cookie_store
      Amber::Server.instance.session = {
        :key     => "name.session",
        :store   => :redis,
        :expires => 120,
        :secret  => "secret",
        :redis_url => "redis://localhost:6379"
      }

      store = SessionFactory.new(cookies)

      store.build.should be_a Session::RedisStore
    end
  end
end
