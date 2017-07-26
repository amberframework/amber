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
                           when :encrypted_cookie
                             encrypted_cookie
                           else
                             signed_cookie
                           end
      end

      def redis
        store = Redis.new(url: session[:redis_url].to_s)
        Session::RedisStore.new(store, cookies, session[:key].to_s, session[:expires].to_i)
      end

      def encrypted_cookie
        Session::CookieStore.new(cookies.encrypted, session[:key].to_s, session[:expires].to_i, session[:secret].to_s)
      end

      def signed_cookie
        Session::CookieStore.new(cookies.signed, session[:key].to_s, session[:expires].to_i, session[:secret].to_s)
      end
    end
  end
end
