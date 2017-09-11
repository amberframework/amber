require "../../../../spec_helper"

module Amber::Router::Session
  COOKIE_STORE = Amber::Router::Cookies::Store.new
  EXPIRES      = 120 # 2 minutes

  describe CookieStore do
    context "Encrypted" do
      describe "#id" do
        it "returns a UUID" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store.id.not_nil!.size.should eq 36
        end
      end

      describe "#destroy" do
        it "clears session" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store.destroy

          cookie_store.empty?.should be_true
        end
      end

      describe "#[]" do
        it "gets key, value" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store[:name] = "John"

          cookie_store[:name].hash.should eq cookie_store["name"].hash
          cookie_store[:name].should eq cookie_store["name"]
          cookie_store["name"].should eq "John"
        end
      end

      describe "#[]?" do
        it "returns true when key exists" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["name"] = "David"

          cookie_store[:name]?.should eq "David"
          cookie_store["name"]?.should eq "David"
        end

        it "returns false when key does not exists" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store[:name]?.should eq nil
          cookie_store["name"]?.should eq nil
        end
      end

      describe "#[]=" do
        it "sets a key value" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["name"] = "David"

          cookie_store[:name].should eq "David"
          cookie_store["name"].should eq "David"
        end

        it "updates key value" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store["name"] = "Frank"

          cookie_store[:name].should eq "Frank"
          cookie_store["name"].should eq "Frank"
        end
      end

      describe "#key?" do
        context "key exists" do
          it "returns true" do
            cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

            cookie_store[:name] = "David"

            cookie_store.key?("David").should eq "name"
          end
        end

        context "key does not exists" do
          it "returns false" do
            cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

            cookie_store.key?(:name).should eq nil
            cookie_store.key?("name").should eq nil
          end
        end
      end

      describe "#keys" do
        it "returns a list of available keys" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["a"] = "a"
          cookie_store[:b] = "c"
          cookie_store["c"] = "c"

          cookie_store.keys.should eq %w(a b c)
        end
      end

      describe "#values" do
        it "returns a list of available keys" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["a"] = "a"
          cookie_store["b"] = "b"
          cookie_store[:c] = "c"

          cookie_store.values.should eq %w(a b c)
        end
      end

      describe "#update" do
        it "updates all keys by hash" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)
          cookie_store["a"] = "a"
          cookie_store["b"] = "b"
          cookie_store[:c] = "c"

          cookie_store.update({"a" => "1", "b" => "2", "c" => "3"})

          cookie_store.values.should eq %w(1 2 3)
        end
      end

      describe "#fetch" do
        context "when key is not set" do
          it "fetches default value" do
            cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

            cookie_store.fetch("name", "Jordan").should eq "Jordan"
          end
        end

        context "when key is set" do
          it "it fetches previously set value" do
            cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

            cookie_store["name"] = "Michael"

            cookie_store.fetch("name", "Jordan").should eq "Michael"
          end
        end
      end

      describe "#empty?" do
        it "returns true when session is empty" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store.empty?.should eq true
        end

        it "returns false when session is not empty" do
          cookie_store = CookieStore.new(COOKIE_STORE.encrypted, "ses", EXPIRES)

          cookie_store["user_id"] = "1"

          cookie_store.empty?.should eq false
        end
      end
    end

    context "Signed" do
      describe "#id" do
        it "returns a UUID" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store.id.not_nil!.size.should eq 36
        end
      end

      describe "#destroy" do
        it "clears session" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store.destroy

          cookie_store.empty?.should be_true
        end
      end

      describe "#[]" do
        it "gets key, value" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store[:name] = "John"

          cookie_store[:name].hash.should eq cookie_store["name"].hash
          cookie_store[:name].should eq cookie_store["name"]
          cookie_store["name"].should eq "John"
        end
      end

      describe "#[]?" do
        it "returns true when key exists" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["name"] = "David"

          cookie_store[:name]?.should eq "David"
          cookie_store["name"]?.should eq "David"
        end

        it "returns false when key does not exists" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store[:name]?.should eq nil
          cookie_store["name"]?.should eq nil
        end
      end

      describe "#[]=" do
        it "sets a key value" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["name"] = "David"

          cookie_store[:name].should eq "David"
          cookie_store["name"].should eq "David"
        end

        it "updates key value" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["name"] = "David"
          cookie_store["name"] = "Frank"

          cookie_store[:name].should eq "Frank"
          cookie_store["name"].should eq "Frank"
        end
      end

      describe "#key?" do
        context "key exists" do
          it "returns true" do
            cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

            cookie_store[:name] = "David"

            cookie_store.key?("David").should eq "name"
          end
        end

        context "key does not exists" do
          it "returns false" do
            cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

            cookie_store.key?(:name).should eq nil
            cookie_store.key?("name").should eq nil
          end
        end
      end

      describe "#keys" do
        it "returns a list of available keys" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["a"] = "a"
          cookie_store[:b] = "c"
          cookie_store["c"] = "c"

          cookie_store.keys.should eq %w(a b c)
        end
      end

      describe "#values" do
        it "returns a list of available keys" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["a"] = "a"
          cookie_store["b"] = "b"
          cookie_store[:c] = "c"

          cookie_store.values.should eq %w(a b c)
        end
      end

      describe "#update" do
        it "updates all keys by hash" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)
          cookie_store["a"] = "a"
          cookie_store["b"] = "b"
          cookie_store[:c] = "c"

          cookie_store.update({"a" => "1", "b" => "2", "c" => "3"})

          cookie_store.values.should eq %w(1 2 3)
        end
      end

      describe "#fetch" do
        context "when key is not set" do
          it "fetches default value" do
            cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

            cookie_store.fetch("name", "Jordan").should eq "Jordan"
          end
        end

        context "when key is set" do
          it "it fetches previously set value" do
            cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

            cookie_store["name"] = "Michael"

            cookie_store.fetch("name", "Jordan").should eq "Michael"
          end
        end
      end

      describe "#empty?" do
        it "returns true when session is empty" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store.empty?.should eq true
        end

        it "returns false when session is not empty" do
          cookie_store = CookieStore.new(COOKIE_STORE.signed, "ses", EXPIRES)

          cookie_store["user_id"] = "1"

          cookie_store.empty?.should eq false
        end
      end
    end
  end
end
