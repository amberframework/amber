require "socket"
require "openssl"
require "base64"

module Amber::Mailer
  # SMTP delivery adapter for sending emails via an SMTP server.
  #
  # Implements the SMTP protocol using Crystal's standard library Socket and
  # OpenSSL modules. Supports STARTTLS for encrypted connections and AUTH LOGIN
  # for authentication.
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
  # 1. Connect to SMTP server
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
    property helo_domain : String

    def initialize(
      @host : String = "localhost",
      @port : Int32 = 25,
      @username : String? = nil,
      @password : String? = nil,
      @use_tls : Bool = false,
      @helo_domain : String = "localhost",
    )
    end

    # Delivers an email by connecting to the SMTP server and transmitting
    # the message using the SMTP protocol.
    #
    # Returns a `DeliveryResult` indicating whether the delivery succeeded.
    # On failure, the error message contains details about what went wrong.
    def deliver(email : Email) : DeliveryResult
      begin
        socket = TCPSocket.new(@host, @port)
      rescue ex : Socket::ConnectError
        return DeliveryResult.new(is_successful: false, error: "SMTP connection failed: #{ex.message}")
      rescue ex : Socket::Error
        return DeliveryResult.new(is_successful: false, error: "SMTP socket error: #{ex.message}")
      end

      io : IO = socket

      begin
        # Read server greeting
        read_response(io, expected_code: 220)

        # Send EHLO
        send_command(io, "EHLO #{@helo_domain}", expected_code: 250)

        # Upgrade to TLS if requested
        if @use_tls
          send_command(io, "STARTTLS", expected_code: 220)
          tls_context = OpenSSL::SSL::Context::Client.new
          tls_socket = OpenSSL::SSL::Socket::Client.new(socket, tls_context, hostname: @host)
          io = tls_socket

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
        io << mime_message
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
      rescue ex : IO::Error
        DeliveryResult.new(is_successful: false, error: "SMTP connection error: #{ex.message}")
      rescue ex : Socket::Error
        DeliveryResult.new(is_successful: false, error: "SMTP socket error: #{ex.message}")
      ensure
        socket.close rescue nil
      end
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
