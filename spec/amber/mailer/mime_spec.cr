require "../../spec_helper"

describe Amber::Mailer::MimeBuilder do
  describe ".build" do
    it "generates headers for a basic email" do
      email = Amber::Mailer::Email.new(
        to: ["alice@example.com"],
        from: "sender@example.com",
        subject: "Test Subject",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("MIME-Version: 1.0")
      mime.should contain("From: sender@example.com")
      mime.should contain("To: alice@example.com")
      mime.should contain("Subject: Test Subject")
      mime.should contain("Date: ")
    end

    it "joins multiple To addresses with commas" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com", "b@example.com"],
        from: "sender@example.com",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("To: a@example.com, b@example.com")
    end

    it "includes Cc header when cc recipients are present" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        cc: ["cc@example.com"],
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("Cc: cc@example.com")
    end

    it "does not include Cc header when cc is empty" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should_not contain("Cc:")
    end

    it "includes Reply-To header when set" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        reply_to: "reply@example.com",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("Reply-To: reply@example.com")
    end

    it "includes custom headers" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        text_body: "Hello",
        headers: {"X-Mailer" => "Amber", "X-Priority" => "1"},
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("X-Mailer: Amber")
      mime.should contain("X-Priority: 1")
    end

    it "encodes non-ASCII subject with RFC 2047" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        subject: "Привет мир",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("Subject: =?UTF-8?B?")
    end

    it "does not encode ASCII-only subject" do
      email = Amber::Mailer::Email.new(
        to: ["a@example.com"],
        from: "sender@example.com",
        subject: "Hello World",
        text_body: "Hello",
      )

      mime = Amber::Mailer::MimeBuilder.build(email)
      mime.should contain("Subject: Hello World")
    end

    context "with text body only" do
      it "generates a single-part text/plain message" do
        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "Test",
          text_body: "Plain text content",
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("Content-Type: text/plain; charset=UTF-8")
        mime.should contain("Plain text content")
        mime.should_not contain("multipart")
      end
    end

    context "with HTML body only" do
      it "generates a single-part text/html message" do
        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "Test",
          html_body: "<h1>Hello</h1>",
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("Content-Type: text/html; charset=UTF-8")
        mime.should contain("<h1>Hello</h1>")
        mime.should_not contain("multipart")
      end
    end

    context "with both text and HTML bodies" do
      it "generates a multipart/alternative message" do
        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "Test",
          text_body: "Plain text",
          html_body: "<h1>HTML</h1>",
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("Content-Type: multipart/alternative")
        mime.should contain("Content-Type: text/plain; charset=UTF-8")
        mime.should contain("Content-Type: text/html; charset=UTF-8")
        mime.should contain("Plain text")
        mime.should contain("<h1>HTML</h1>")
      end
    end

    context "with attachments" do
      it "generates a multipart/mixed message" do
        attachment = Amber::Mailer::Attachment.new(
          filename: "test.txt",
          content: "file content".to_slice,
          mime_type: "text/plain",
        )

        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "Test",
          text_body: "See attached",
          attachments: [attachment],
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("Content-Type: multipart/mixed")
        mime.should contain("See attached")
        mime.should contain("Content-Disposition: attachment; filename=\"test.txt\"")
        mime.should contain("Content-Transfer-Encoding: base64")
      end

      it "base64 encodes attachment content" do
        content = "hello world".to_slice
        expected_b64 = Base64.strict_encode(content)

        attachment = Amber::Mailer::Attachment.new(
          filename: "test.txt",
          content: content,
          mime_type: "text/plain",
        )

        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          text_body: "See attached",
          attachments: [attachment],
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain(expected_b64)
      end

      it "wraps multipart/alternative inside multipart/mixed when both bodies and attachments exist" do
        attachment = Amber::Mailer::Attachment.new(
          filename: "doc.pdf",
          content: Bytes.new(10),
          mime_type: "application/pdf",
        )

        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          text_body: "Plain text",
          html_body: "<p>HTML</p>",
          attachments: [attachment],
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("Content-Type: multipart/mixed")
        mime.should contain("Content-Type: multipart/alternative")
        mime.should contain("Content-Type: text/plain; charset=UTF-8")
        mime.should contain("Content-Type: text/html; charset=UTF-8")
        mime.should contain("Content-Disposition: attachment; filename=\"doc.pdf\"")
      end

      it "handles multiple attachments" do
        attachments = [
          Amber::Mailer::Attachment.new(filename: "a.txt", content: "aaa".to_slice, mime_type: "text/plain"),
          Amber::Mailer::Attachment.new(filename: "b.bin", content: "bbb".to_slice, mime_type: "application/octet-stream"),
        ]

        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          text_body: "Files",
          attachments: attachments,
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("filename=\"a.txt\"")
        mime.should contain("filename=\"b.bin\"")
      end
    end

    context "edge cases" do
      it "handles empty bodies" do
        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "No body",
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should contain("From: sender@example.com")
        mime.should contain("Subject: No body")
      end

      it "handles empty string bodies as no body" do
        email = Amber::Mailer::Email.new(
          to: ["a@example.com"],
          from: "sender@example.com",
          subject: "Test",
          text_body: "",
          html_body: "",
        )

        mime = Amber::Mailer::MimeBuilder.build(email)
        mime.should_not contain("multipart")
      end
    end
  end

  describe ".generate_boundary" do
    it "generates a unique boundary string" do
      b1 = Amber::Mailer::MimeBuilder.generate_boundary
      b2 = Amber::Mailer::MimeBuilder.generate_boundary
      b1.should_not eq(b2)
    end

    it "generates a boundary with the Amber prefix" do
      boundary = Amber::Mailer::MimeBuilder.generate_boundary
      boundary.should start_with("----=_Amber_")
    end
  end
end
