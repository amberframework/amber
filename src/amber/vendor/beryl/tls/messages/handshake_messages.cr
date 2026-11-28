require "./message_reader"

module Amber::Beryl::TLS::Messages
  # The fixed random of a HelloRetryRequest (RFC 9846 §4.1.3): SHA-256 of
  # "HelloRetryRequest".
  HELLO_RETRY_REQUEST_RANDOM = Bytes[
    0xCF, 0x21, 0xAD, 0x74, 0xE5, 0x9A, 0x61, 0x11, 0xBE, 0x1D, 0x8C, 0x02, 0x1E, 0x65, 0xB8, 0x91,
    0xC2, 0xA2, 0x11, 0x16, 0x7A, 0xBB, 0x8C, 0x5E, 0x07, 0x9E, 0x09, 0xE2, 0xC8, 0xA8, 0x33, 0x9C,
  ]

  # One extension: its type number and its raw contents.
  record Extension, type_value : UInt16, contents : Bytes do
    def type? : ExtensionType?
      ExtensionType.from_value?(type_value)
    end
  end

  # Wraps *body* in a handshake message header.
  def self.wrap(handshake_type : HandshakeType, body : Bytes) : Bytes
    message = Bytes.new(4 + body.size)
    message[0] = handshake_type.value
    message[1] = (body.size >> 16).to_u8
    message[2] = ((body.size >> 8) & 0xFF).to_u8
    message[3] = (body.size & 0xFF).to_u8
    body.copy_to(message + 4)
    message
  end

  # Returns the type and body of a whole handshake *message* (as
  # `RecordLayer#read_handshake_message` returns it).
  def self.unwrap(message : Bytes) : {HandshakeType?, Bytes}
    raise Error.new("a handshake message of #{message.size} bytes", AlertDescription::DecodeError) if message.size < 4
    {HandshakeType.from_value?(message[0]), message[4..]}
  end

  # Reads an extensions block (a two-byte length, then entries). A type
  # that appears twice is refused (RFC 9846 §4.2).
  def self.read_extensions(reader : MessageReader) : Array(Extension)
    list_of_extensions = [] of Extension
    # A set, so a block of many extensions is checked in linear time.
    seen_type_values = Set(UInt16).new
    block = MessageReader.new(reader.read_vector16)
    until block.at_end?
      type_value = block.read_u16
      contents = block.read_vector16
      unless seen_type_values.add?(type_value)
        raise Error.new("the extension #{type_value} appears twice", AlertDescription::IllegalParameter)
      end
      list_of_extensions << Extension.new(type_value, contents)
    end
    list_of_extensions
  end

  def self.write_extensions(writer : MessageWriter, list_of_extensions : Array(Extension)) : Nil
    writer.write_vector16 do |block|
      list_of_extensions.each do |extension|
        block.write_u16(extension.type_value)
        block.write_vector16(extension.contents)
      end
    end
  end

  # What every message with extensions shares.
  module HasExtensions
    abstract def list_of_extensions : Array(Extension)

    # Returns the contents of the extension *type*, or nil.
    def extension(type : ExtensionType) : Bytes?
      list_of_extensions.find { |extension| extension.type_value == type.value }.try(&.contents)
    end

    def has_extension?(type : ExtensionType) : Bool
      list_of_extensions.any? { |extension| extension.type_value == type.value }
    end
  end

  # ClientHello (RFC 9846 §4.1.2).
  class ClientHello
    include HasExtensions

    property legacy_version : UInt16 = ProtocolVersion::TLS_1_2
    property random : Bytes
    property legacy_session_id : Bytes
    property list_of_cipher_suites : Array(UInt16)
    property legacy_compression_methods : Bytes = Bytes[0]
    property list_of_extensions : Array(Extension)

    def initialize(@random : Bytes, @legacy_session_id : Bytes, @list_of_cipher_suites : Array(UInt16), @list_of_extensions : Array(Extension))
    end

    def self.decode(body : Bytes) : ClientHello
      reader = MessageReader.new(body)
      legacy_version = reader.read_u16
      random = reader.read_bytes(32)
      session_id = reader.read_vector8
      raise Error.new("a session id of #{session_id.size} bytes", AlertDescription::DecodeError) if session_id.size > 32
      suites = MessageReader.new(reader.read_vector16(2))
      raise Error.new("an odd-length cipher suite list", AlertDescription::DecodeError) if suites.remaining.odd?
      list_of_suites = Array(UInt16).new(suites.remaining // 2) { suites.read_u16 }
      compression = reader.read_vector8(1)
      # A TLS 1.0 hello may end without extensions; TLS 1.3 needs them,
      # which the caller checks through supported_versions.
      list_of_extensions = reader.at_end? ? [] of Extension : Messages.read_extensions(reader)
      reader.finish
      hello = ClientHello.new(random, session_id, list_of_suites, list_of_extensions)
      hello.legacy_version = legacy_version
      hello.legacy_compression_methods = compression
      hello
    end

    # Returns the whole message, header included.
    def encode : Bytes
      writer = MessageWriter.new
      writer.write_u16(@legacy_version)
      writer.write_bytes(@random)
      writer.write_vector8(@legacy_session_id)
      writer.write_vector16 { |suites| @list_of_cipher_suites.each { |suite| suites.write_u16(suite) } }
      writer.write_vector8(@legacy_compression_methods)
      Messages.write_extensions(writer, @list_of_extensions)
      Messages.wrap(HandshakeType::ClientHello, writer.to_slice)
    end

    # The size of the message, header included, up to the binders of its
    # pre_shared_key extension (the part a PSK binder covers, §4.2.11.2).
    # The extension is last, so its binders list closes the message.
    def self.binder_prefix_bytesize(message : Bytes, binders : Array(Bytes)) : Int32
      message.size - (2 + binders.sum { |binder| 1 + binder.size })
    end
  end

  # ServerHello and HelloRetryRequest (RFC 9846 §4.1.3, §4.1.4).
  class ServerHello
    include HasExtensions

    property legacy_version : UInt16 = ProtocolVersion::TLS_1_2
    property random : Bytes
    property legacy_session_id_echo : Bytes
    property cipher_suite : UInt16
    property legacy_compression_method : UInt8 = 0_u8
    property list_of_extensions : Array(Extension)

    def initialize(@random : Bytes, @legacy_session_id_echo : Bytes, @cipher_suite : UInt16, @list_of_extensions : Array(Extension))
    end

    def hello_retry_request? : Bool
      @random == HELLO_RETRY_REQUEST_RANDOM
    end

    def self.decode(body : Bytes) : ServerHello
      reader = MessageReader.new(body)
      legacy_version = reader.read_u16
      random = reader.read_bytes(32)
      session_id = reader.read_vector8
      raise Error.new("a session id of #{session_id.size} bytes", AlertDescription::DecodeError) if session_id.size > 32
      suite = reader.read_u16
      compression = reader.read_u8
      list_of_extensions = reader.at_end? ? [] of Extension : Messages.read_extensions(reader)
      reader.finish
      hello = ServerHello.new(random, session_id, suite, list_of_extensions)
      hello.legacy_version = legacy_version
      hello.legacy_compression_method = compression
      hello
    end

    def encode : Bytes
      writer = MessageWriter.new
      writer.write_u16(@legacy_version)
      writer.write_bytes(@random)
      writer.write_vector8(@legacy_session_id_echo)
      writer.write_u16(@cipher_suite)
      writer.write_u8(@legacy_compression_method)
      Messages.write_extensions(writer, @list_of_extensions)
      Messages.wrap(HandshakeType::ServerHello, writer.to_slice)
    end
  end

  # EncryptedExtensions (RFC 9846 §4.3.1).
  class EncryptedExtensions
    include HasExtensions

    getter list_of_extensions : Array(Extension)

    def initialize(@list_of_extensions : Array(Extension))
    end

    def self.decode(body : Bytes) : EncryptedExtensions
      reader = MessageReader.new(body)
      list_of_extensions = Messages.read_extensions(reader)
      reader.finish
      EncryptedExtensions.new(list_of_extensions)
    end

    def encode : Bytes
      writer = MessageWriter.new
      Messages.write_extensions(writer, @list_of_extensions)
      Messages.wrap(HandshakeType::EncryptedExtensions, writer.to_slice)
    end
  end

  # One CertificateEntry: DER certificate data and its extensions.
  record CertificateEntry, certificate_data : Bytes, list_of_extensions : Array(Extension)

  # Certificate (RFC 9846 §4.4.2), X.509 entries only.
  class CertificateMessage
    getter certificate_request_context : Bytes
    getter list_of_entries : Array(CertificateEntry)

    def initialize(@certificate_request_context : Bytes, @list_of_entries : Array(CertificateEntry))
    end

    # Reads the message; *largest_count* and *largest_bytesize* bound the
    # certificate list (plan §4).
    def self.decode(body : Bytes, *, largest_count : Int32 = 10, largest_bytesize : Int32 = 65_536) : CertificateMessage
      reader = MessageReader.new(body)
      context = reader.read_vector8
      list_bytes = reader.read_vector24
      reader.finish
      if list_bytes.size > largest_bytesize
        raise Error.new("a certificate list of #{list_bytes.size} bytes", AlertDescription::BadCertificate)
      end
      list = MessageReader.new(list_bytes)
      list_of_entries = [] of CertificateEntry
      until list.at_end?
        certificate_data = list.read_vector24(1)
        list_of_extensions = Messages.read_extensions(list)
        list_of_entries << CertificateEntry.new(certificate_data, list_of_extensions)
        if list_of_entries.size > largest_count
          raise Error.new("more than #{largest_count} certificates", AlertDescription::BadCertificate)
        end
      end
      CertificateMessage.new(context, list_of_entries)
    end

    def encode : Bytes
      writer = MessageWriter.new
      writer.write_vector8(@certificate_request_context)
      writer.write_vector24 do |list|
        @list_of_entries.each do |entry|
          list.write_vector24(entry.certificate_data)
          Messages.write_extensions(list, entry.list_of_extensions)
        end
      end
      Messages.wrap(HandshakeType::Certificate, writer.to_slice)
    end
  end

  # CertificateRequest (RFC 9846 §4.3.2).
  class CertificateRequest
    include HasExtensions

    getter certificate_request_context : Bytes
    getter list_of_extensions : Array(Extension)

    def initialize(@certificate_request_context : Bytes, @list_of_extensions : Array(Extension))
    end

    def self.decode(body : Bytes) : CertificateRequest
      reader = MessageReader.new(body)
      context = reader.read_vector8
      list_of_extensions = Messages.read_extensions(reader)
      reader.finish
      CertificateRequest.new(context, list_of_extensions)
    end

    def encode : Bytes
      writer = MessageWriter.new
      writer.write_vector8(@certificate_request_context)
      Messages.write_extensions(writer, @list_of_extensions)
      Messages.wrap(HandshakeType::CertificateRequest, writer.to_slice)
    end
  end

  # CertificateVerify (RFC 9846 §4.4.3).
  class CertificateVerify
    getter signature_scheme_value : UInt16
    getter signature : Bytes

    def initialize(@signature_scheme_value : UInt16, @signature : Bytes)
    end

    # An empty signature is well formed (`opaque signature<0..2^16-1>`) and
    # fails verification, so it ends the handshake with decrypt_error.
    def self.decode(body : Bytes) : CertificateVerify
      reader = MessageReader.new(body)
      scheme = reader.read_u16
      signature = reader.read_vector16
      reader.finish
      CertificateVerify.new(scheme, signature)
    end

    def encode : Bytes
      writer = MessageWriter.new
      writer.write_u16(@signature_scheme_value)
      writer.write_vector16(@signature)
      Messages.wrap(HandshakeType::CertificateVerify, writer.to_slice)
    end

    # The bytes a CertificateVerify signs: 64 spaces, the context string, a
    # zero byte and the transcript hash (§4.4.3).
    def self.signed_content(transcript_digest : Bytes, *, is_server : Bool) : Bytes
      context = is_server ? "TLS 1.3, server CertificateVerify" : "TLS 1.3, client CertificateVerify"
      content = Bytes.new(64 + context.bytesize + 1 + transcript_digest.size, 0x20_u8)
      context.to_slice.copy_to(content + 64)
      content[64 + context.bytesize] = 0
      transcript_digest.copy_to(content + (65 + context.bytesize))
      content
    end
  end

  # Finished (RFC 9846 §4.4.4).
  class Finished
    getter verify_data : Bytes

    def initialize(@verify_data : Bytes)
    end

    def self.decode(body : Bytes, hash_bytesize : Int32) : Finished
      raise Error.new("a Finished of #{body.size} bytes", AlertDescription::DecodeError) unless body.size == hash_bytesize
      Finished.new(body)
    end

    def encode : Bytes
      Messages.wrap(HandshakeType::Finished, @verify_data)
    end
  end

  # NewSessionTicket (RFC 9846 §4.6.1).
  class NewSessionTicket
    include HasExtensions

    getter ticket_lifetime : UInt32
    getter ticket_age_add : UInt32
    getter ticket_nonce : Bytes
    getter ticket : Bytes
    getter list_of_extensions : Array(Extension)

    def initialize(@ticket_lifetime : UInt32, @ticket_age_add : UInt32, @ticket_nonce : Bytes, @ticket : Bytes,
                   @list_of_extensions : Array(Extension) = [] of Extension)
    end

    def self.decode(body : Bytes) : NewSessionTicket
      reader = MessageReader.new(body)
      lifetime = reader.read_u32
      age_add = reader.read_u32
      nonce = reader.read_vector8
      ticket = reader.read_vector16(1)
      list_of_extensions = Messages.read_extensions(reader)
      reader.finish
      NewSessionTicket.new(lifetime, age_add, nonce, ticket, list_of_extensions)
    end

    def encode : Bytes
      writer = MessageWriter.new
      writer.write_u32(@ticket_lifetime)
      writer.write_u32(@ticket_age_add)
      writer.write_vector8(@ticket_nonce)
      writer.write_vector16(@ticket)
      Messages.write_extensions(writer, @list_of_extensions)
      Messages.wrap(HandshakeType::NewSessionTicket, writer.to_slice)
    end
  end

  # KeyUpdate (RFC 9846 §4.6.3).
  class KeyUpdate
    getter request : KeyUpdateRequest

    def initialize(@request : KeyUpdateRequest)
    end

    def self.decode(body : Bytes) : KeyUpdate
      raise Error.new("a KeyUpdate of #{body.size} bytes", AlertDescription::DecodeError) unless body.size == 1
      request = KeyUpdateRequest.from_value?(body[0]) || raise Error.new("a KeyUpdate request of #{body[0]}", AlertDescription::IllegalParameter)
      KeyUpdate.new(request)
    end

    def encode : Bytes
      Messages.wrap(HandshakeType::KeyUpdate, Bytes[@request.value])
    end
  end
end
