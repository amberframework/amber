require "../../spec_helper"

# Test mailer with both HTML and text bodies.
class TestWelcomeMailer < Amber::Mailer::Base
  def initialize(@user_name : String)
  end

  def html_body : String?
    "<h1>Welcome, #{@user_name}!</h1><p>Thanks for signing up.</p>"
  end

  def text_body : String?
    "Welcome, #{@user_name}! Thanks for signing up."
  end
end

# Test mailer with only a text body.
class TextOnlyMailer < Amber::Mailer::Base
  def html_body : String?
    nil
  end

  def text_body : String?
    "Plain text only"
  end
end

# Test mailer with only an HTML body.
class HtmlOnlyMailer < Amber::Mailer::Base
  def html_body : String?
    "<p>HTML only</p>"
  end

  def text_body : String?
    nil
  end
end

# Test mailer with no body content.
class EmptyMailer < Amber::Mailer::Base
  def html_body : String?
    nil
  end

  def text_body : String?
    nil
  end
end

describe Amber::Mailer::Base do
  before_each do
    Amber::Mailer::MemoryAdapter.clear
    Amber::Mailer::Configuration.reset
  end

  describe "fluent API" do
    it "sets recipients with #to" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.to("alice@example.com")
      result.should be(mailer)
      mailer.list_of_recipients.should eq(["alice@example.com"])
    end

    it "sets multiple recipients with #to" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer.to("a@example.com", "b@example.com")
      mailer.list_of_recipients.should eq(["a@example.com", "b@example.com"])
    end

    it "sets sender with #from" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.from("sender@example.com")
      result.should be(mailer)
      mailer.sender.should eq("sender@example.com")
    end

    it "sets subject with #subject" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.subject("Welcome!")
      result.should be(mailer)
      mailer.email_subject.should eq("Welcome!")
    end

    it "sets cc recipients with #cc" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.cc("cc1@example.com", "cc2@example.com")
      result.should be(mailer)
      mailer.list_of_cc_recipients.should eq(["cc1@example.com", "cc2@example.com"])
    end

    it "sets bcc recipients with #bcc" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.bcc("bcc@example.com")
      result.should be(mailer)
      mailer.list_of_bcc_recipients.should eq(["bcc@example.com"])
    end

    it "sets reply_to with #reply_to" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.reply_to("reply@example.com")
      result.should be(mailer)
      mailer.reply_to_address.should eq("reply@example.com")
    end

    it "adds custom headers with #header" do
      mailer = TestWelcomeMailer.new("Alice")
      result = mailer.header("X-Custom", "value")
      result.should be(mailer)
      mailer.custom_headers["X-Custom"].should eq("value")
    end

    it "supports method chaining" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer
        .to("alice@example.com")
        .from("sender@example.com")
        .subject("Welcome!")
        .cc("cc@example.com")
        .bcc("bcc@example.com")
        .reply_to("reply@example.com")
        .header("X-Test", "true")

      mailer.list_of_recipients.should eq(["alice@example.com"])
      mailer.sender.should eq("sender@example.com")
      mailer.email_subject.should eq("Welcome!")
      mailer.list_of_cc_recipients.should eq(["cc@example.com"])
      mailer.list_of_bcc_recipients.should eq(["bcc@example.com"])
      mailer.reply_to_address.should eq("reply@example.com")
      mailer.custom_headers["X-Test"].should eq("true")
    end
  end

  describe "#attach" do
    it "adds an attachment" do
      mailer = TestWelcomeMailer.new("Alice")
      content = "file data".to_slice
      result = mailer.attach("test.txt", content, "text/plain")

      result.should be(mailer)
      mailer.list_of_attachments.size.should eq(1)
      mailer.list_of_attachments[0].filename.should eq("test.txt")
      mailer.list_of_attachments[0].content.should eq(content)
      mailer.list_of_attachments[0].mime_type.should eq("text/plain")
    end

    it "defaults mime_type to application/octet-stream" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer.attach("data.bin", Bytes.new(4))
      mailer.list_of_attachments[0].mime_type.should eq("application/octet-stream")
    end

    it "supports multiple attachments" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer.attach("a.txt", "aaa".to_slice)
      mailer.attach("b.txt", "bbb".to_slice)
      mailer.list_of_attachments.size.should eq(2)
    end
  end

  describe "#build" do
    it "builds an Email struct from the mailer state" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer
        .to("alice@example.com")
        .from("sender@example.com")
        .subject("Welcome!")
        .cc("cc@example.com")
        .bcc("bcc@example.com")
        .reply_to("reply@example.com")

      email = mailer.build
      email.to.should eq(["alice@example.com"])
      email.from.should eq("sender@example.com")
      email.subject.should eq("Welcome!")
      email.cc.should eq(["cc@example.com"])
      email.bcc.should eq(["bcc@example.com"])
      email.reply_to.should eq("reply@example.com")
      email.html_body.not_nil!.should contain("Welcome, Alice!")
      email.text_body.should eq("Welcome, Alice! Thanks for signing up.")
    end

    it "uses default_from when from is not set" do
      Amber::Mailer::Configuration.configure do |config|
        config.default_from = "default@myapp.com"
      end

      mailer = TestWelcomeMailer.new("Alice")
      mailer.to("alice@example.com").subject("Test")

      email = mailer.build
      email.from.should eq("default@myapp.com")
    end

    it "prefers explicitly set from over default_from" do
      Amber::Mailer::Configuration.configure do |config|
        config.default_from = "default@myapp.com"
      end

      mailer = TestWelcomeMailer.new("Alice")
      mailer.to("alice@example.com").from("explicit@myapp.com").subject("Test")

      email = mailer.build
      email.from.should eq("explicit@myapp.com")
    end

    it "includes attachments in the built email" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer
        .to("alice@example.com")
        .from("sender@example.com")
        .attach("test.txt", "data".to_slice, "text/plain")

      email = mailer.build
      email.attachments.size.should eq(1)
      email.attachments[0].filename.should eq("test.txt")
    end
  end

  describe "#deliver" do
    it "delivers an email using the configured adapter" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer
        .to("alice@example.com")
        .from("sender@example.com")
        .subject("Welcome!")

      result = mailer.deliver
      result.is_successful.should be_true

      Amber::Mailer::MemoryAdapter.count.should eq(1)
      delivered = Amber::Mailer::MemoryAdapter.last.not_nil!
      delivered.to.should eq(["alice@example.com"])
      delivered.from.should eq("sender@example.com")
      delivered.subject.should eq("Welcome!")
    end

    it "delivers text-only emails" do
      mailer = TextOnlyMailer.new
      mailer.to("user@example.com").from("sender@example.com").subject("Text")

      result = mailer.deliver
      result.is_successful.should be_true

      delivered = Amber::Mailer::MemoryAdapter.last.not_nil!
      delivered.text_body.should eq("Plain text only")
      delivered.html_body.should be_nil
    end

    it "delivers HTML-only emails" do
      mailer = HtmlOnlyMailer.new
      mailer.to("user@example.com").from("sender@example.com").subject("HTML")

      result = mailer.deliver
      result.is_successful.should be_true

      delivered = Amber::Mailer::MemoryAdapter.last.not_nil!
      delivered.html_body.should eq("<p>HTML only</p>")
      delivered.text_body.should be_nil
    end

    it "delivers emails with no body" do
      mailer = EmptyMailer.new
      mailer.to("user@example.com").from("sender@example.com").subject("Empty")

      result = mailer.deliver
      result.is_successful.should be_true

      delivered = Amber::Mailer::MemoryAdapter.last.not_nil!
      delivered.html_body.should be_nil
      delivered.text_body.should be_nil
    end

    it "delivers emails with attachments" do
      mailer = TestWelcomeMailer.new("Alice")
      mailer
        .to("alice@example.com")
        .from("sender@example.com")
        .subject("With attachment")
        .attach("report.pdf", "pdf content".to_slice, "application/pdf")

      result = mailer.deliver
      result.is_successful.should be_true

      delivered = Amber::Mailer::MemoryAdapter.last.not_nil!
      delivered.attachments.size.should eq(1)
      delivered.attachments[0].filename.should eq("report.pdf")
    end
  end
end
