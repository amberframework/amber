require "../../../../spec_helper"
require "redis"

# TODO: This test can't run on it's own because it needs the EXPIRES contant which is set elsewhere.
module Amber::Router::Session
  REDIS_STORE = Redis.new(url: Settings.redis_url)

  describe RedisStore do
    describe "#id" do
      it "returns a UUID" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)
        cookie_store.set_session

        cookie_store.id.size.should eq 36
      end
    end

    describe "#destroy" do
      it "clears session" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"] = "david"
        cookie_store.destroy

        cookie_store.empty?.should be_true
      end
    end

    describe "#[]" do
      it "gets key, value" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"] = "david"
        cookie_store["name"].should eq "david"
      end

      it "throws error if key does not exists" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        expect_raises KeyError do
          cookie_store["name"]
        end

        expect_raises KeyError do
          cookie_store[:name]
        end
      end
    end

    describe "#[]?" do
      it "returns true when key exists" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"] = "david"

        cookie_store["name"]?.should eq "david"
      end

      it "returns false when key does not exists" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"]?.should eq nil
      end
    end

    describe "#[]=" do
      it "sets a key value" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"] = "david"

        cookie_store["name"].should eq "david"
      end

      it "updates key value" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["name"] = "david"
        cookie_store["name"] = "frank"

        cookie_store["name"].should eq "frank"
      end
    end

    describe "#key?" do
      context "key exists" do
        it "returns true" do
          cookies = new_cookie_store
          cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

          cookie_store["name"] = "david"

          cookie_store.key?("name").should eq true
        end
      end

      context "key does not exists" do
        it "returns false" do
          cookies = new_cookie_store
          cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

          cookie_store.key?("name").should eq false
        end
      end
    end

    describe "#keys" do
      it "returns a list of available keys" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["a"] = "a"
        cookie_store["b"] = "c"
        cookie_store["c"] = "c"

        cookie_store.keys.should eq %w(a b c)
      end
    end

    describe "#values" do
      it "returns a list of available keys" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store["a"] = "a"
        cookie_store["b"] = "b"
        cookie_store["c"] = "c"

        cookie_store.delete("ses")

        cookie_store.values.should eq %w(a b c)
      end
    end

    describe "#update" do
      it "updates all keys by hash" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)
        cookie_store["a"] = "a"
        cookie_store["b"] = "b"
        cookie_store["c"] = "c"

        cookie_store.update({"a" => "1", "b" => "2", "c" => "3"})
        cookie_store.delete("ses")

        cookie_store.values.should eq %w(1 2 3)
      end
    end

    describe "#fetch" do
      context "when key is not set" do
        it "fetches default value" do
          cookies = new_cookie_store
          cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

          cookie_store.fetch("name", "Jordan").should eq "Jordan"
        end
      end

      context "when key is set" do
        it "it fetches previously set value" do
          cookies = new_cookie_store
          cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

          cookie_store["name"] = "Michael"

          cookie_store.fetch("name", "Jordan").should eq "Michael"
        end
      end
    end

    describe "#empty?" do
      it "returns true when session is empty" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store.set_session

        cookie_store.empty?.should eq true
      end

      it "returns false when session is not empty" do
        cookies = new_cookie_store
        cookie_store = RedisStore.new(REDIS_STORE, cookies, "ses", EXPIRES)

        cookie_store.set_session
        cookie_store["user_id"] = "1"

        cookie_store.empty?.should eq false
      end
    end
  end
end
