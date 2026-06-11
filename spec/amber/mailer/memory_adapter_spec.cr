require "../../spec_helper"

describe Amber::Mailer::MemoryAdapter do
  before_each do
    Amber::Mailer::MemoryAdapter.clear
  end

  describe "#deliver" do
    it "stores the email in deliveries" do
      adapter = Amber::Mailer::MemoryAdapter.new
      email = Amber::Mailer::Email.new(
        to: ["alice@example.com"],
        from: "sender@example.com",
        subject: "Test",
        text_body: "Hello",
      )

      result = adapter.deliver(email)
      result.is_successful.should be_true
      Amber::Mailer::MemoryAdapter.count.should eq(1)
    end

    it "returns a successful delivery result" do
      adapter = Amber::Mailer::MemoryAdapter.new
      email = Amber::Mailer::Email.new(to: ["a@example.com"], from: "b@example.com")

      result = adapter.deliver(email)
      result.is_successful.should be_true
      result.error.should be_nil
    end
  end

  describe ".deliveries" do
    it "returns all delivered emails" do
      adapter = Amber::Mailer::MemoryAdapter.new

      3.times do |i|
        email = Amber::Mailer::Email.new(
          to: ["user#{i}@example.com"],
          from: "sender@example.com",
          subject: "Email #{i}",
        )
        adapter.deliver(email)
      end

      deliveries = Amber::Mailer::MemoryAdapter.deliveries
      deliveries.size.should eq(3)
      deliveries[0].subject.should eq("Email 0")
      deliveries[1].subject.should eq("Email 1")
      deliveries[2].subject.should eq("Email 2")
    end

    it "returns a copy of the deliveries array" do
      adapter = Amber::Mailer::MemoryAdapter.new
      email = Amber::Mailer::Email.new(to: ["a@example.com"], from: "b@example.com")
      adapter.deliver(email)

      deliveries = Amber::Mailer::MemoryAdapter.deliveries
      deliveries.clear
      Amber::Mailer::MemoryAdapter.count.should eq(1)
    end
  end

  describe ".clear" do
    it "removes all stored deliveries" do
      adapter = Amber::Mailer::MemoryAdapter.new
      email = Amber::Mailer::Email.new(to: ["a@example.com"], from: "b@example.com")
      adapter.deliver(email)
      adapter.deliver(email)

      Amber::Mailer::MemoryAdapter.count.should eq(2)
      Amber::Mailer::MemoryAdapter.clear
      Amber::Mailer::MemoryAdapter.count.should eq(0)
    end
  end

  describe ".last" do
    it "returns the most recently delivered email" do
      adapter = Amber::Mailer::MemoryAdapter.new

      email1 = Amber::Mailer::Email.new(
        to: ["first@example.com"],
        from: "sender@example.com",
        subject: "First",
      )
      email2 = Amber::Mailer::Email.new(
        to: ["second@example.com"],
        from: "sender@example.com",
        subject: "Second",
      )

      adapter.deliver(email1)
      adapter.deliver(email2)

      last = Amber::Mailer::MemoryAdapter.last
      last.should_not be_nil
      last.not_nil!.subject.should eq("Second")
    end

    it "returns nil when no emails have been delivered" do
      Amber::Mailer::MemoryAdapter.last.should be_nil
    end
  end

  describe ".count" do
    it "returns the number of delivered emails" do
      Amber::Mailer::MemoryAdapter.count.should eq(0)

      adapter = Amber::Mailer::MemoryAdapter.new
      email = Amber::Mailer::Email.new(to: ["a@example.com"], from: "b@example.com")

      adapter.deliver(email)
      Amber::Mailer::MemoryAdapter.count.should eq(1)

      adapter.deliver(email)
      Amber::Mailer::MemoryAdapter.count.should eq(2)
    end
  end
end
