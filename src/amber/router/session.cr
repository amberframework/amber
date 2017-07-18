module Amber::Router
  module Session
    class Store
      property session : Hash(Symbol, Symbol | Int32 | String)
      property cookies : Cookies::Store
      getter session_store : Session::AbstractStore?

      def initialize(@cookies)
        @session = Amber::Server.session
      end

      def build : Session::AbstractStore
        @session_store ||= case session[:store]
                           when :redis
                             redis
                           else
                             cookie
                           end
      end

      def redis
        store = Redis.new(url: session[:redis_url].to_s)
        Session::RedisStore.new(store, cookies, session[:key].to_s, session[:expires].to_i)
      end

      def cookie
        Session::CookieStore.new(cookies, session[:key].to_s, session[:expires].to_i, session[:secret].to_s)
      end
    end
  end
end
