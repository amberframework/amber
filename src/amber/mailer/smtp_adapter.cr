require "socket"
require "base64"

module Amber::Mailer
  # SMTP delivery adapter for sending emails via an SMTP server.
  #
  # Implements the SMTP protocol using Crystal's standard library Socket.
  # Supports STARTTLS (`use_tls`, port 587) and implicit TLS
  # (`use_implicit_tls`, port 465), which need `require "amber/tls"` in the
  # app, and AUTH LOGIN for authentication. TLS is TLS 1.3 only: the server's
  # certificate chain and name are verified, against the Mozilla roots or the
  # certificates in `ca_certificates_file`, and a server that offers no TLS
  # 1.3 fails delivery with an error that names the requirement.
  #
  # ## Usage
  #
  # ```
  # adapter = SMTPAdapter.new(
  #   host: "smtp.example.com",
  #   port: 587,
  #   username: "user@example.com",
  #   password: "secret",
  #   use_tls: true,
  #   helo_domain: "myapp.com"
  # )
  #
  # result = adapter.deliver(email)
  # ```
  #
  # ## SMTP Protocol Flow
  #
  # 1. Connect to SMTP server (and start TLS at once with `use_implicit_tls`)
  # 2. Read server greeting (220)
  # 3. Send EHLO
  # 4. Optionally upgrade to TLS via STARTTLS
  # 5. Re-send EHLO after TLS upgrade
  # 6. Authenticate via AUTH LOGIN if credentials are provided
  # 7. Send MAIL FROM, RCPT TO, DATA commands
  # 8. Send the MIME message
  # 9. Send QUIT
  class SMTPAdapter < DeliveryAdapter
    property host : String
    property port : Int32
    property username : String?
    property password : String?
    property use_tls : Bool
    property use_implicit_tls : Bool
    property ca_certificates_file : String?
    property helo_domain : String

    def initialize(
      @host : String = "localhost",
      @port : Int32 = 25,
      @username : String? = nil,
      @password : String? = nil,
      @use_tls : Bool = false,
      @helo_domain : String = "localhost",
      @use_implicit_tls : Bool = false,
      @ca_certificates_file : String? = nil,
    )
    end

    # Delivers an email by connecting to the SMTP server and transmitting
    # the message using the SMTP protocol.
    #
    # Returns a `DeliveryResult` indicating whether the delivery succeeded.
    # On failure, the error message contains details about what went wrong.
    def deliver(email : Email) : DeliveryResult
      # Refused before connecting when the app does not require "amber/tls".
      {% unless Amber::TLS.has_constant?(:Backend) %}
        if @use_tls || @use_implicit_tls
          raise Amber::Exceptions::TLSNotCompiledIn.new(Amber::TLS::STARTTLS)
        end
      {% end %}

      begin
        socket = TCPSocket.new(@host, @port)
      rescue ex : Socket::ConnectError
        return DeliveryResult.new(is_successful: false, error: "SMTP connection failed: #{ex.message}")
      rescue ex : Socket::Error
        return DeliveryResult.new(is_successful: false, error: "SMTP socket error: #{ex.message}")
      end

      io : IO = socket

      begin
        # Implicit TLS starts before the greeting (RFC 8314).
        io = start_tls(socket) if @use_implicit_tls

        # Read server greeting
        read_response(io, expected_code: 220)

        # Send EHLO
        send_command(io, "EHLO #{@helo_domain}", expected_code: 250)

        # Upgrade to TLS if requested
        if @use_tls && !@use_implicit_tls
          send_command(io, "STARTTLS", expected_code: 220)
          io = start_tls(socket)

          # Re-send EHLO after TLS upgrade
          send_command(io, "EHLO #{@helo_domain}", expected_code: 250)
        end

        # Authenticate if credentials are provided
        if (user = @username) && (pass = @password)
          send_command(io, "AUTH LOGIN", expected_code: 334)
          send_command(io, Base64.strict_encode(user), expected_code: 334)
          send_command(io, Base64.strict_encode(pass), expected_code: 235)
        end

        # Send envelope
        send_command(io, "MAIL FROM:<#{email.from}>", expected_code: 250)

        email.all_recipients.each do |recipient|
          send_command(io, "RCPT TO:<#{recipient}>", expected_code: 250)
        end

        # Send message data
        send_command(io, "DATA", expected_code: 354)

        mime_message = email.to_mime
        io << dot_stuffed(mime_message)
        # Ensure the message ends with CRLF.CRLF
        unless mime_message.ends_with?("\r\n")
          io << "\r\n"
        end
        send_command(io, ".", expected_code: 250)

        # Quit
        send_command(io, "QUIT", expected_code: 221)

        DeliveryResult.new(is_successful: true)
      rescue ex : SMTPError
        DeliveryResult.new(is_successful: false, error: ex.message)
      rescue ex : Amber::TLS::ClientSessionFailed
        DeliveryResult.new(is_successful: false, error: "SMTP #{ex.message}")
      rescue ex : IO::Error
        DeliveryResult.new(is_successful: false, error: "SMTP connection error: #{ex.message}")
      rescue ex : Socket::Error
        DeliveryResult.new(is_successful: false, error: "SMTP socket error: #{ex.message}")
      ensure
        begin
          io.close unless io.same?(socket)
        rescue IO::Error
        end
        socket.close rescue nil
      end
    end

    # RFC 5321 section 4.5.2: a message line that starts with "." gets one more
    # "." in front, so the server does not take it for the end of DATA (and
    # removes the added dot on receipt).
    private def dot_stuffed(message : String) : String
      String.build do |io|
        message.each_line(chomp: false) do |line|
          io << '.' if line.starts_with?('.')
          io << line
        end
      end
    end

    # Starts TLS 1.3 over *socket*, verifying the server's certificate
    # against `host`.
    private def start_tls(socket : TCPSocket) : IO
      # Expanded when this method is instantiated, after every file is
      # required, so `require "amber/tls"` may come before or after
      # `require "amber"`.
      {% if Amber::TLS.has_constant?(:Backend) %}
        Amber::TLS::Backend.start_client_session(socket, @host, @ca_certificates_file)
      {% else %}
        raise Amber::Exceptions::TLSNotCompiledIn.new(Amber::TLS::STARTTLS)
      {% end %}
    end

    # Sends a command to the SMTP server and reads the response.
    #
    # Raises `SMTPError` if the response code does not match the expected code.
    private def send_command(io : IO, command : String, expected_code : Int32) : String
      io << command << "\r\n"
      io.flush
      read_response(io, expected_code: expected_code)
    end

    # Reads a response from the SMTP server.
    #
    # Handles multi-line responses (lines with a dash continuation character)
    # and verifies the response code matches the expected value.
    #
    # Raises `SMTPError` if the response code does not match the expected code.
    private def read_response(io : IO, expected_code : Int32) : String
      response = String.build do |buffer|
        loop do
          line = io.gets
          raise SMTPError.new("SMTP server closed connection unexpectedly") if line.nil?
          buffer << line << "\n"

          # SMTP multi-line responses use "XXX-" format; last line uses "XXX "
          break if line.size >= 4 && line[3]? == ' '
        end
      end

      response_code = response[0, 3].to_i?
      unless response_code == expected_code
        raise SMTPError.new("Expected SMTP response #{expected_code}, got: #{response.strip}")
      end

      response
    end
  end

  # Raised when an SMTP protocol error occurs during email delivery.
  class SMTPError < Exception
  end
end
