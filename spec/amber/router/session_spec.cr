require "../../spec_helper"
include SessionHelper

module Amber::Router
  describe Session::Store do
    it "creates a cookie session store for signed_cookie" do
      session = create_session_config("signed_cookie")
      store = Session::Store.new(new_cookie_store, session)

      store.build.should be_a Session::CookieStore
      store.build.as(Session::CookieStore).store.should be_a Cookies::SignedStore
    end

    it "creates a cookie session store for encrypted_cookie" do
      session = create_session_config("encrypted_cookie")
      store = Session::Store.new(new_cookie_store, session)

      store.build.as(Session::CookieStore).store.should be_a Cookies::EncryptedStore
    end

    it "creates an adapter session store with the memory adapter for store: adapter" do
      session = create_session_config("adapter")
      store = Session::Store.new(new_cookie_store, session)
      adapter_store = store.build.as(Session::AdapterSessionStore)

      adapter_store.adapter.should be_a Amber::Adapters::MemorySessionAdapter
    end

    {"signed_cookie", "encrypted_cookie"}.each do |cookie_store_name|
      it "keeps a #{cookie_store_name} session in the cookie and nothing on the server" do
        with_session_store(cookie_store_name) do
          sessions_before = shared_memory_session_adapter.size

          first_context = create_context(HTTP::Request.new("GET", "/"))
          first_context.session["user_id"] = "42"
          Amber::Pipe::Session.new.call(first_context)

          shared_memory_session_adapter.size.should eq sessions_before
          first_context.response.headers.has_key?("Set-Cookie").should be_true

          second_request = HTTP::Request.new("GET", "/", browser_headers_after(first_context.response.headers))
          second_context = create_context(second_request)
          second_context.session["user_id"]?.should eq "42"
          shared_memory_session_adapter.size.should eq sessions_before
        end
      end
    end
  end
end
