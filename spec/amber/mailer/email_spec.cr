require "../../spec_helper"

describe Amber::Mailer::Email do
  describe "#initialize" do
    it "creates an email with default values" do
      email = Amber::Mailer::Email.new
      email.to.should eq([] of String)
      email.from.should eq("")
      email.subject.should eq("")
      email.cc.should eq([] of String)
      email.bcc.should eq([] of String)
      email.reply_to.should be_nil
      email.html_body.should be_nil
      email.text_body.should be_nil
      email.headers.should eq({} of String => String)
      email.attachments.should eq([] of Amber::Mailer::Attachment)
    end

    it "creates an email with specified values" do
      email = Amber::Mailer::Email.new(
        to: ["alice@example.com"],
        from: "sender@example.com",
        subject: "Hello",
        cc: ["bob@example.com"],
        bcc: ["carol@example.com"],
        reply_to: "reply@example.com",
        html_body: "<h1>Hi</h1>",
        text_body: "Hi",
        headers: {"X-Custom" => "value"},
      )

      email.to.should eq(["alice@example.com"])
      email.from.should eq("sender@example.com")
      email.subject.should eq("Hello")
      email.cc.should eq(["bob@example.com"])
      email.bcc.should eq(["carol@example.com"])
      email.reply_to.should eq("reply@example.com")
      email.html_body.should eq("<h1>Hi</h1>")
      email.text_body.should eq("Hi")
      email.headers.should eq({"X-Custom" => "value"})
    end
  end

  describe "#all_recipients" do
    it "returns combined to, cc, and bcc addresses" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com", "b@example.com"],
        cc: ["c@example.com"],
        bcc: ["d@example.com"],
      )

      recipients = email.all_recipients
      recipients.should contain("a@example.com")
      recipients.should contain("b@example.com")
      recipients.should contain("c@example.com")
      recipients.should contain("d@example.com")
      recipients.size.should eq(4)
    end

    it "returns only to addresses when cc and bcc are empty" do
      email = Amber::Mailer::Email.new(to: ["a@example.com"])
      email.all_recipients.should eq(["a@example.com"])
    end
  end

  describe "#to_mime" do
    it "generates a MIME message string" do
      email = Amber::Mailer::Email.new(
        to: ["alice@example.com"],
        from: "sender@example.com",
        subject: "Test",
        text_body: "Hello",
      )

      mime = email.to_mime
      mime.should contain("From: sender@example.com")
      mime.should contain("To: alice@example.com")
      mime.should contain("Subject: Test")
      mime.should contain("Hello")
    end
  end
end

describe Amber::Mailer::Attachment do
  it "stores filename, content, and mime_type" do
    content = "hello".to_slice
    attachment = Amber::Mailer::Attachment.new(
      filename: "test.txt",
      content: content,
      mime_type: "text/plain",
    )

    attachment.filename.should eq("test.txt")
    attachment.content.should eq(content)
    attachment.mime_type.should eq("text/plain")
  end

  it "defaults mime_type to application/octet-stream" do
    attachment = Amber::Mailer::Attachment.new(
      filename: "data.bin",
      content: Bytes.new(4),
    )

    attachment.mime_type.should eq("application/octet-stream")
  end
end

describe Amber::Mailer::DeliveryResult do
  it "creates a successful result" do
    result = Amber::Mailer::DeliveryResult.new(is_successful: true)
    result.is_successful.should be_true
    result.error.should be_nil
  end

  it "creates a failed result with error" do
    result = Amber::Mailer::DeliveryResult.new(is_successful: false, error: "Connection refused")
    result.is_successful.should be_false
    result.error.should eq("Connection refused")
  end

  it "defaults to successful" do
    result = Amber::Mailer::DeliveryResult.new
    result.is_successful.should be_true
  end
end
