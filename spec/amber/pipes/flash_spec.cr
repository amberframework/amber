require "../../spec_helper"
require "json"
include SessionHelper

module Amber
  module Pipe
    describe Flash do
      # A flash with no messages must not create a session, whichever store
      # holds sessions.
      {"signed_cookie", "encrypted_cookie", "adapter"}.each do |store|
        context "with store: #{store}" do
          it "leaves no session when the flash is empty" do
            with_session_store(store) do
              sessions_before = shared_memory_session_adapter.size
              context = create_context(HTTP::Request.new("GET", "/"))

              serve_through_session_and_flash(context) { |_context| }

              context.response.headers.has_key?("Set-Cookie").should be_false
              shared_memory_session_adapter.size.should eq sessions_before
            end
          end

          it "carries a flash message to the next request, then clears it once read" do
            with_session_store(store) do
              first_context = create_context(HTTP::Request.new("POST", "/"))
              serve_through_session_and_flash(first_context) do |context|
                context.flash[:notice] = "Saved"
              end
              first_context.response.headers.has_key?("Set-Cookie").should be_true

              second_request = HTTP::Request.new("GET", "/", browser_headers_after(first_context.response.headers))
              second_context = create_context(second_request)
              notice_shown = nil
              serve_through_session_and_flash(second_context) do |context|
                notice_shown = context.flash[:notice]?
              end
              notice_shown.should eq "Saved"
              second_context.session.has_key?(Flash::PARAM_KEY).should be_false

              second_context.response.headers.has_key?("Set-Cookie").should be_true

              third_request = HTTP::Request.new("GET", "/", browser_headers_after(second_context.response.headers))
              third_context = create_context(third_request)
              notice_after_read = "unread"
              serve_through_session_and_flash(third_context) do |context|
                notice_after_read = context.flash[:notice]?
              end
              notice_after_read.should be_nil
            end
          end
        end
      end
    end
  end

  module Router
    describe Flash::FlashStore do
      describe ".from_session" do
        it "creates a flash store from json" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.has_key?("some_key").should be_true
          flash_store["some_key"].should eq "some_value"
        end

        it "returns an empty flash store if json is invalid" do
          json = "some_key=some_value"
          flash_store = Flash::FlashStore.from_session json

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#fetch" do
        it "returns the value" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch("some_key").should eq "some_value"
        end

        it "supports symbols" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch(:some_key).should eq "some_value"
        end

        it "returns the default value" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch(:some_other_key, "default").should eq "default"
        end

        it "marks the value as read" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key")
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end

        it "marks the value as read for default value implementation" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key", nil)
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#each" do
        it "returns the list of key/value pairs" do
          flashes = {"some_key" => "some_value", "other_key" => "other_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          test = Hash(String, String).new
          flash_store.each { |k, v| test[k] = v }
          test.size.should eq 2
        end

        it "marks the keys as read" do
          flashes = {"some_key" => "some_value", "other_key" => "other_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          test = Hash(String, String).new
          flash_store.each { |k, v| test[k] = v }
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#now" do
        it "does not keep key even if never read" do
          flash_store = Flash::FlashStore.new
          flash_store.now("some_key", "some_value")
          flash_store = Flash::FlashStore.from_session flash_store.to_session
          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#keep" do
        it "keeps the key after being read" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key")
          flash_store.keep("some_key")
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_true
        end
      end

      describe "<< Hash" do
        it "supports [] with String" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store["some_key"].should eq "some_value"
        end

        it "supports [] with Symbol" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store[:some_key].should eq "some_value"
        end

        it "supports []= with String" do
          flash_store = Flash::FlashStore.new
          flash_store["some_key"] = "some_value"

          flash_store["some_key"].should eq "some_value"
        end

        it "supports []= with Symbol" do
          flash_store = Flash::FlashStore.new
          flash_store[:some_key] = "some_value"

          flash_store[:some_key].should eq "some_value"
        end

        it "supports []= with Symbol but reading with String" do
          flash_store = Flash::FlashStore.new
          flash_store[:some_key] = "some_value"

          flash_store["some_key"].should eq "some_value"
        end

        it "supports []? with Symbol" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store[:some_other_key]?.should eq nil
          flash_store[:some_key]?.should eq "some_value"
        end

        it "supports []? with String" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store["some_other_key"]?.should eq nil
          flash_store["some_key"]?.should eq "some_value"
        end
      end
    end
  end
end
