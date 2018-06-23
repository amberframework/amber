require "../../../../spec_helper"

module Amber::Router::Session
  cookie_store = Amber::Router::Cookies::Store.new

  [cookie_store.encrypted, cookie_store.signed].each do |store_type|
    subject = CookieStore.new(store_type, "ses", 120)

    describe CookieStore do
      context "#{store_type.class}" do
        Spec.before_each do
          subject.destroy
        end

        describe "#id" do
          it "returns a UUID" do
            subject.id.not_nil!.size.should eq 36
          end
        end

        describe "#destroy" do
          it "clears session" do
            subject["name"] = "David"
            subject.destroy

            subject.empty?.should be_true
          end
        end

        describe "#[]" do
          it "accepts string as key" do
            subject["name"] = "Fake Name"

            subject["name"].should eq "Fake Name"
          end

          it "accepts symbol as key" do
            subject[:name] = "Fake Name"

            subject[:name].should eq "Fake Name"
          end

          it "gets key, value" do
            subject["name"] = "David"
            subject[:name] = "John"

            subject["name"].should eq "John"
          end
        end

        describe "#[]?" do
          it "returns true when key exists" do
            subject["name"] = "David"

            subject[:name]?.should eq "David"
          end

          it "returns false when key does not exists" do
            subject[:name]?.should eq nil
          end
        end

        describe "#[]=" do
          it "sets a key value" do
            subject["name"] = "David"

            subject["name"].should eq "David"
          end

          it "updates key value" do
            subject["name"] = "David"
            subject["name"] = "Frank"

            subject[:name].should eq "Frank"
          end
        end

        describe "#key_for?" do
          context "key exists" do
            it "returns true" do
              subject[:name] = "David"

              subject.key_for?("David").should eq "name"
            end
          end

          context "key does not exists" do
            it "returns false" do
              subject.key_for?(:name).should eq nil
              subject.key_for?("name").should eq nil
            end
          end
        end

        describe "#keys" do
          it "returns a list of available keys" do
            subject["a"] = "a"
            subject[:b] = "c"
            subject["c"] = "c"

            subject.keys.should eq %w(a b c)
          end
        end

        describe "#values" do
          it "returns a list of available keys" do
            subject["a"] = "a"
            subject["b"] = "b"
            subject[:c] = "c"

            subject.values.should eq %w(a b c)
          end
        end

        describe "#update" do
          it "updates all keys by hash" do
            subject["a"] = "a"
            subject["b"] = "b"
            subject[:c] = "c"

            subject.update({"a" => "1", "b" => "2", "c" => "3"})

            subject.values.should eq %w(1 2 3)
          end
        end

        describe "#fetch" do
          context "when key is not set" do
            it "fetches default value" do
              subject.fetch("name", "Jordan").should eq "Jordan"
            end
          end

          context "when key is set" do
            it "it fetches previously set value" do
              subject["name"] = "Michael"

              subject.fetch("name", "Jordan").should eq "Michael"
            end
          end
        end

        describe "#empty?" do
          it "returns true when session is empty" do
            subject.empty?.should eq true
          end

          it "returns false when session is not empty" do
            subject["user_id"] = "1"

            subject.empty?.should eq false
          end
        end
      end
    end
  end
end
