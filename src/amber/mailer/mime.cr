require "base64"
require "random/secure"

module Amber::Mailer
  # Builds RFC 2045-compliant MIME messages from Email structs.
  #
  # Handles the generation of multipart email messages including:
  # - Single-part text or HTML messages
  # - Multipart/alternative messages with both text and HTML
  # - Multipart/mixed messages with file attachments
  # - Base64 encoding of binary attachments
  # - Proper MIME boundary generation using secure random values
  #
  # This module is used internally by `Email#to_mime` and should not
  # typically be called directly.
  module MimeBuilder
    CRLF = "\r\n"

    # Builds a complete MIME message string from an Email struct.
    #
    # The generated message includes all required headers (From, To, Subject,
    # MIME-Version, Date) plus any custom headers, followed by the message body
    # in the appropriate MIME structure.
    def self.build(email : Email) : String
      String.build do |io|
        write_headers(io, email)
        io << CRLF

        if email.attachments.empty?
          write_body_without_attachments(io, email)
        else
          write_body_with_attachments(io, email)
        end
      end
    end

    # Writes standard and custom email headers to the IO.
    private def self.write_headers(io : IO, email : Email) : Nil
      io << "MIME-Version: 1.0" << CRLF
      io << "Date: " << Time.utc.to_rfc2822 << CRLF
      io << "From: " << email.from << CRLF
      io << "To: " << email.to.join(", ") << CRLF
      io << "Subject: " << encode_header_value(email.subject) << CRLF

      unless email.cc.empty?
        io << "Cc: " << email.cc.join(", ") << CRLF
      end

      if reply_to = email.reply_to
        io << "Reply-To: " << reply_to << CRLF
      end

      email.headers.each do |name, value|
        io << name << ": " << value << CRLF
      end
    end

    # Writes the email body when no attachments are present.
    #
    # Selects the appropriate MIME structure:
    # - Both text and HTML: multipart/alternative
    # - Only HTML: single-part text/html
    # - Only text: single-part text/plain
    # - Neither: empty body
    private def self.write_body_without_attachments(io : IO, email : Email) : Nil
      has_text = !email.text_body.nil? && !email.text_body.try(&.empty?)
      has_html = !email.html_body.nil? && !email.html_body.try(&.empty?)

      if has_text && has_html
        boundary = generate_boundary
        io << "Content-Type: multipart/alternative; boundary=\"" << boundary << "\"" << CRLF
        io << CRLF
        write_text_part(io, boundary, email.text_body.not_nil!)
        write_html_part(io, boundary, email.html_body.not_nil!)
        io << "--" << boundary << "--" << CRLF
      elsif has_html
        io << "Content-Type: text/html; charset=UTF-8" << CRLF
        io << "Content-Transfer-Encoding: quoted-printable" << CRLF
        io << CRLF
        io << email.html_body.not_nil!
      elsif has_text
        io << "Content-Type: text/plain; charset=UTF-8" << CRLF
        io << "Content-Transfer-Encoding: quoted-printable" << CRLF
        io << CRLF
        io << email.text_body.not_nil!
      end
    end

    # Writes the email body when attachments are present.
    #
    # Uses multipart/mixed as the top-level content type, with the body
    # content (text/html) nested inside and attachments as separate parts.
    private def self.write_body_with_attachments(io : IO, email : Email) : Nil
      mixed_boundary = generate_boundary

      io << "Content-Type: multipart/mixed; boundary=\"" << mixed_boundary << "\"" << CRLF
      io << CRLF

      has_text = !email.text_body.nil? && !email.text_body.try(&.empty?)
      has_html = !email.html_body.nil? && !email.html_body.try(&.empty?)

      # Write body part(s)
      if has_text && has_html
        alt_boundary = generate_boundary
        io << "--" << mixed_boundary << CRLF
        io << "Content-Type: multipart/alternative; boundary=\"" << alt_boundary << "\"" << CRLF
        io << CRLF
        write_text_part(io, alt_boundary, email.text_body.not_nil!)
        write_html_part(io, alt_boundary, email.html_body.not_nil!)
        io << "--" << alt_boundary << "--" << CRLF
      elsif has_html
        io << "--" << mixed_boundary << CRLF
        io << "Content-Type: text/html; charset=UTF-8" << CRLF
        io << "Content-Transfer-Encoding: quoted-printable" << CRLF
        io << CRLF
        io << email.html_body.not_nil! << CRLF
      elsif has_text
        io << "--" << mixed_boundary << CRLF
        io << "Content-Type: text/plain; charset=UTF-8" << CRLF
        io << "Content-Transfer-Encoding: quoted-printable" << CRLF
        io << CRLF
        io << email.text_body.not_nil! << CRLF
      end

      # Write attachment parts
      email.attachments.each do |attachment|
        write_attachment_part(io, mixed_boundary, attachment)
      end

      io << "--" << mixed_boundary << "--" << CRLF
    end

    # Writes a text/plain MIME part within a multipart boundary.
    private def self.write_text_part(io : IO, boundary : String, text : String) : Nil
      io << "--" << boundary << CRLF
      io << "Content-Type: text/plain; charset=UTF-8" << CRLF
      io << "Content-Transfer-Encoding: quoted-printable" << CRLF
      io << CRLF
      io << text << CRLF
    end

    # Writes a text/html MIME part within a multipart boundary.
    private def self.write_html_part(io : IO, boundary : String, html : String) : Nil
      io << "--" << boundary << CRLF
      io << "Content-Type: text/html; charset=UTF-8" << CRLF
      io << "Content-Transfer-Encoding: quoted-printable" << CRLF
      io << CRLF
      io << html << CRLF
    end

    # Writes a base64-encoded attachment MIME part within a multipart boundary.
    private def self.write_attachment_part(io : IO, boundary : String, attachment : Attachment) : Nil
      io << "--" << boundary << CRLF
      io << "Content-Type: " << attachment.mime_type << "; name=\"" << attachment.filename << "\"" << CRLF
      io << "Content-Transfer-Encoding: base64" << CRLF
      io << "Content-Disposition: attachment; filename=\"" << attachment.filename << "\"" << CRLF
      io << CRLF

      encoded = Base64.strict_encode(attachment.content)
      # Split base64 into 76-character lines per RFC 2045
      offset = 0
      while offset < encoded.size
        line_end = Math.min(offset + 76, encoded.size)
        io << encoded[offset...line_end] << CRLF
        offset = line_end
      end
    end

    # Generates a unique MIME boundary string using cryptographically secure random bytes.
    def self.generate_boundary : String
      "----=_Amber_#{Random::Secure.hex(16)}"
    end

    # Encodes a header value using RFC 2047 encoded-word syntax if it contains
    # non-ASCII characters. ASCII-only values are returned unchanged.
    private def self.encode_header_value(value : String) : String
      if value.each_char.all?(&.ascii?)
        value
      else
        "=?UTF-8?B?#{Base64.strict_encode(value)}?="
      end
    end
  end
end
