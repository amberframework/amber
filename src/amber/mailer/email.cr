module Amber::Mailer
  # Represents a file attachment to be included in an email message.
  #
  # Attachments are encoded as base64 in the MIME message body and included
  # as separate MIME parts with appropriate Content-Disposition headers.
  #
  # ## Example
  #
  # ```
  # attachment = Attachment.new(
  #   filename: "report.pdf",
  #   content: File.read("report.pdf").to_slice,
  #   mime_type: "application/pdf"
  # )
  # ```
  struct Attachment
    property filename : String
    property content : Bytes
    property mime_type : String

    def initialize(@filename : String, @content : Bytes, @mime_type : String = "application/octet-stream")
    end
  end

  # Represents a fully constructed email message ready for delivery.
  #
  # An Email contains all the headers, body content, and attachments needed
  # to generate a complete MIME message. Emails are typically built by the
  # `Base` mailer class and passed to a `DeliveryAdapter` for sending.
  #
  # ## Example
  #
  # ```
  # email = Email.new(
  #   to: ["user@example.com"],
  #   from: "app@example.com",
  #   subject: "Hello",
  #   html_body: "<h1>Hello!</h1>",
  #   text_body: "Hello!"
  # )
  #
  # mime_message = email.to_mime
  # ```
  struct Email
    property to : Array(String)
    property from : String
    property subject : String
    property cc : Array(String)
    property bcc : Array(String)
    property reply_to : String?
    property html_body : String?
    property text_body : String?
    property headers : Hash(String, String)
    property attachments : Array(Attachment)

    def initialize(
      @to : Array(String) = [] of String,
      @from : String = "",
      @subject : String = "",
      @cc : Array(String) = [] of String,
      @bcc : Array(String) = [] of String,
      @reply_to : String? = nil,
      @html_body : String? = nil,
      @text_body : String? = nil,
      @headers : Hash(String, String) = {} of String => String,
      @attachments : Array(Attachment) = [] of Attachment,
    )
    end

    # Generates a complete MIME-formatted email message string.
    #
    # The MIME structure depends on the content present:
    # - Text only: single-part text/plain
    # - HTML only: single-part text/html
    # - Text + HTML: multipart/alternative
    # - With attachments: multipart/mixed wrapping the body parts
    def to_mime : String
      MimeBuilder.build(self)
    end

    # Returns all recipient addresses (to + cc + bcc) for SMTP envelope delivery.
    def all_recipients : Array(String)
      to + cc + bcc
    end
  end

  # Represents the result of an email delivery attempt.
  #
  # Contains a success flag and an optional error message for failed deliveries.
  struct DeliveryResult
    property is_successful : Bool
    property error : String?

    def initialize(@is_successful : Bool = true, @error : String? = nil)
    end
  end
end
