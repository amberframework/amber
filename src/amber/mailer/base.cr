module Amber::Mailer
  # Abstract base class for all application mailers.
  #
  # Provides a fluent API for composing and delivering email messages. Subclasses
  # must implement `html_body` and `text_body` to define the email content.
  #
  # ## Usage
  #
  # ```
  # class WelcomeMailer < Amber::Mailer::Base
  #   def initialize(@user_name : String, @user_email : String)
  #   end
  #
  #   def html_body : String?
  #     "<h1>Welcome, #{HTML.escape(@user_name)}!</h1>"
  #   end
  #
  #   def text_body : String?
  #     "Welcome, #{@user_name}!"
  #   end
  # end
  #
  # mailer = WelcomeMailer.new("Alice", "alice@example.com")
  # mailer.to("alice@example.com").from("hello@myapp.com").subject("Welcome!").deliver
  # ```
  #
  # ## Fluent API
  #
  # All setter methods return `self` to enable method chaining:
  #
  # ```
  # mailer.to("a@example.com", "b@example.com")
  #   .from("noreply@example.com")
  #   .subject("Update")
  #   .cc("manager@example.com")
  #   .deliver
  # ```
  abstract class Base
    getter list_of_recipients : Array(String) = [] of String
    getter sender : String = ""
    getter email_subject : String = ""
    getter list_of_cc_recipients : Array(String) = [] of String
    getter list_of_bcc_recipients : Array(String) = [] of String
    getter reply_to_address : String? = nil
    getter custom_headers : Hash(String, String) = {} of String => String
    getter list_of_attachments : Array(Attachment) = [] of Attachment

    # Returns the HTML body content for this email, or nil if no HTML body.
    #
    # Subclasses should override this method to provide HTML content.
    # The content is NOT auto-escaped; the developer is responsible for
    # escaping user-provided data.
    abstract def html_body : String?

    # Returns the plain text body content for this email, or nil if no text body.
    #
    # Subclasses should override this method to provide plain text content.
    abstract def text_body : String?

    # Sets the recipient addresses for this email.
    #
    # Multiple addresses can be provided as separate arguments.
    # Calling this method replaces any previously set recipients.
    def to(*addresses : String) : self
      @list_of_recipients = addresses.to_a
      self
    end

    # Sets the sender address for this email.
    #
    # If not set, the default_from address from the mailer configuration
    # will be used when building the email.
    def from(address : String) : self
      @sender = address
      self
    end

    # Sets the subject line for this email.
    def subject(text : String) : self
      @email_subject = text
      self
    end

    # Sets the CC (carbon copy) recipient addresses for this email.
    #
    # Multiple addresses can be provided as separate arguments.
    # Calling this method replaces any previously set CC recipients.
    def cc(*addresses : String) : self
      @list_of_cc_recipients = addresses.to_a
      self
    end

    # Sets the BCC (blind carbon copy) recipient addresses for this email.
    #
    # Multiple addresses can be provided as separate arguments.
    # BCC recipients are not visible to other recipients.
    # Calling this method replaces any previously set BCC recipients.
    def bcc(*addresses : String) : self
      @list_of_bcc_recipients = addresses.to_a
      self
    end

    # Sets the Reply-To address for this email.
    #
    # When set, email clients will use this address instead of the From
    # address when the recipient clicks Reply.
    def reply_to(address : String) : self
      @reply_to_address = address
      self
    end

    # Adds a custom header to this email.
    #
    # Custom headers are included in the generated MIME message.
    # Standard headers (From, To, Subject, etc.) should be set using
    # their dedicated methods rather than this one.
    def header(name : String, value : String) : self
      @custom_headers[name] = value
      self
    end

    # Attaches binary content as a file attachment.
    #
    # The content is base64-encoded in the generated MIME message.
    #
    # ## Parameters
    #
    # - `filename` - The filename to use in the Content-Disposition header
    # - `content` - The raw binary content of the file
    # - `mime_type` - The MIME type of the file (defaults to "application/octet-stream")
    def attach(filename : String, content : Bytes, mime_type : String = "application/octet-stream") : self
      @list_of_attachments << Attachment.new(filename: filename, content: content, mime_type: mime_type)
      self
    end

    # Attaches a file from the filesystem.
    #
    # Reads the file content and determines a filename automatically.
    # If `filename` is not provided, the basename of the path is used.
    #
    # ## Parameters
    #
    # - `path` - The filesystem path to the file
    # - `filename` - Optional override for the attachment filename
    # - `mime_type` - The MIME type of the file (defaults to "application/octet-stream")
    #
    # ## Raises
    #
    # Raises `File::NotFoundError` if the file does not exist.
    def attach_file(path : String, filename : String? = nil, mime_type : String = "application/octet-stream") : self
      resolved_filename = filename || File.basename(path)
      content = File.read(path).to_slice
      attach(resolved_filename, content, mime_type)
    end

    # Builds an `Email` struct from the current mailer state.
    #
    # Populates the sender from the configuration default if not explicitly set.
    # This method is called automatically by `deliver` but can be used directly
    # to inspect the email before sending.
    def build : Email
      effective_from = @sender.empty? ? Configuration.instance.default_from : @sender

      Email.new(
        to: @list_of_recipients,
        from: effective_from,
        subject: @email_subject,
        cc: @list_of_cc_recipients,
        bcc: @list_of_bcc_recipients,
        reply_to: @reply_to_address,
        html_body: html_body,
        text_body: text_body,
        headers: @custom_headers,
        attachments: @list_of_attachments,
      )
    end

    # Delivers the email using the configured delivery adapter.
    #
    # Builds the email and sends it through the adapter specified
    # in the mailer configuration.
    #
    # ## Returns
    #
    # A `DeliveryResult` indicating whether the delivery succeeded.
    def deliver : DeliveryResult
      email = build
      adapter = Configuration.instance.build_adapter
      adapter.deliver(email)
    end
  end
end
