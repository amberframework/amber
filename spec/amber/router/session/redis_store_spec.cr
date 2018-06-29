require "../../../../spec_helper"
require "redis"

module Amber::Router::Session
  cookies = new_cookie_store.encrypted
  subject = RedisStore.new(cookies, "ses", 120)

  describe RedisStore do
    Spec.before_each do
      subject.destroy
    end

    describe "#id" do
      it "returns a UUID" do
        subject.set_session

        subject.id.size.should eq 36
      end
    end

    describe "#destroy" do
      it "clears session" do
        subject["name"] = "david"
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
    end
    it "gets key, value" do
      subject["name"] = "david"
      subject["name"].should eq "david"
    end

    it "throws error if key does not exists" do
      expect_raises KeyError do
        subject["name"]
      end
    end
  end

  describe "#[]?" do
    it "returns key value when key exists" do
      subject["name"] = "david"

      subject["name"]?.should eq "david"
    end

    it "returns false when key does not exists" do
      subject["name"]?.should be_falsey
    end
  end

  describe "#[]=" do
    it "sets a key value" do
      subject["name"] = "david"

      subject["name"].should eq "david"
    end

    it "updates key value" do
      subject["name"] = "david"
      subject["name"] = "frank"

      subject["name"].should eq "frank"
    end
  end

  describe "#has_key?" do
    context "key exists" do
      it "returns true" do
        subject["name"] = "david"

        subject.has_key?("name").should eq true
      end
    end

    context "key does not exists" do
      it "returns false" do
        subject.has_key?("name").should eq false
      end
    end
  end

  describe "#keys" do
    it "returns a list of available keys" do
      subject["a"] = "a"
      subject["b"] = "c"
      subject["c"] = "c"

      subject.keys.should eq %w(a b c)
    end
  end

  describe "#values" do
    it "returns a list of available keys" do
      subject["a"] = "a"
      subject["b"] = "b"
      subject["c"] = "c"

      subject.delete("ses")

      subject.values.should eq %w(a b c)
    end
  end

  describe "#update" do
    it "updates all keys by hash" do
      subject["a"] = "a"
      subject["b"] = "b"
      subject["c"] = "c"

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
      subject.set_session

      subject.empty?.should eq true
    end

    it "returns false when session is not empty" do
      subject.set_session
      subject["user_id"] = "1"

      subject.empty?.should eq false
    end
  end
end
