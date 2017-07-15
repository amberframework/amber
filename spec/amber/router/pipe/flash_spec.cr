require "../../../../spec_helper"
require "json"

module Amber
  module Pipe
    describe Flash do
    end
  end

  module Router
    describe Flash::FlashStore do
      describe ".from_session_value" do
        it "sweeps the flash store when accessed" do
          discard = ["some_key"].to_set
          flashes = {"some_key" => "some_value"}
          json = {"flashes" => flashes, "discard" => discard}.to_json
          flash_store = Flash::FlashStore.from_session_value json

          flash_store["some_key"].should be_nil
          flash_store[:some_key].should be_nil
          flash_store.has_key?("some_key").should be_falsey
        end
      end
    end
  end
end
