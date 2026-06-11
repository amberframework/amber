require "../../spec_helper"
include SessionHelper

module Amber::Router
  describe Session::Store do
    it "creates an adapter session store by default" do
      session = create_session_config("memory")
      cookies = new_cookie_store
      store = Session::Store.new(cookies, session)

      store.build.should be_a Session::AdapterSessionStore
    end

    it "creates an adapter session store with memory adapter" do
      session = create_session_config("memory")
      cookies = new_cookie_store
      store = Session::Store.new(cookies, session)
      adapter_store = store.build.as(Session::AdapterSessionStore)

      adapter_store.adapter.should be_a Amber::Adapters::MemorySessionAdapter
    end
  end
end
