require "../crypto"
require "./messages/message_reader"
require "./certificate_verifier"

module Amber::Beryl::TLS
  # What a server seals into a session ticket, and reads back when a client
  # offers it (RFC 9846 §4.6.1, §4.2.11). The server keeps no state: the
  # ticket is XChaCha20-Poly1305 under the context's ticket key.
  struct SealedSessionState
    # A version byte at the front, so a later format can coexist.
    FORMAT_VERSION = 1_u8
    # Authenticated with every ticket, so a ticket key used elsewhere
    # cannot be confused with this one.
    ASSOCIATED_DATA = "beryl tls13 session ticket"
    # The longest lifetime RFC 9846 §4.6.1 allows: seven days.
    LONGEST_LIFETIME_SECONDS = 604_800_u32

    getter cipher_suite : CipherSuite
    getter resumption_pre_shared_key : Bytes
    getter issued_at_unix_milliseconds : Int64
    getter lifetime_seconds : UInt32
    getter ticket_age_add : UInt32
    getter alpn_protocol : String?
    getter server_name : String?

    def initialize(@cipher_suite, @resumption_pre_shared_key, @issued_at_unix_milliseconds, @lifetime_seconds,
                   @ticket_age_add, @alpn_protocol, @server_name)
    end

    # Returns the sealed ticket.
    def seal(ticket_key : Bytes) : Bytes
      writer = Messages::MessageWriter.new
      writer.write_u8(FORMAT_VERSION)
      writer.write_u16(@cipher_suite.value)
      writer.write_vector8(@resumption_pre_shared_key)
      writer.write_u32((@issued_at_unix_milliseconds >> 32).to_u32!)
      writer.write_u32((@issued_at_unix_milliseconds & 0xFFFF_FFFF).to_u32!)
      writer.write_u32(@lifetime_seconds)
      writer.write_u32(@ticket_age_add)
      writer.write_vector8((@alpn_protocol || "").to_slice)
      writer.write_vector8((@server_name || "").to_slice)
      plaintext = writer.to_slice
      sealed = Crypto.encrypt(plaintext, key: ticket_key, associated_data: ASSOCIATED_DATA)
      Crypto::SecretWiping.wipe(plaintext)
      sealed
    end

    # Returns the state sealed in *ticket*, or nil for a ticket this key
    # did not seal or that does not parse.
    def self.open(ticket : Bytes, ticket_key : Bytes) : SealedSessionState?
      plaintext = Crypto.decrypt(ticket, key: ticket_key, associated_data: ASSOCIATED_DATA)
      return nil unless plaintext
      reader = Messages::MessageReader.new(plaintext)
      return nil unless reader.read_u8 == FORMAT_VERSION
      suite = CipherSuite.from_value?(reader.read_u16)
      return nil unless suite
      pre_shared_key = reader.read_vector8.dup
      issued_at = (reader.read_u32.to_i64 << 32) | reader.read_u32.to_i64
      lifetime = reader.read_u32
      age_add = reader.read_u32
      alpn = String.new(reader.read_vector8)
      server_name = String.new(reader.read_vector8)
      reader.finish
      Crypto::SecretWiping.wipe(plaintext)
      new(suite, pre_shared_key, issued_at, lifetime, age_add, alpn.empty? ? nil : alpn, server_name.empty? ? nil : server_name)
    rescue Error
      nil
    end
  end

  # A ticket a client holds for one server name, with the verifier that
  # checked the server it came from: a ticket is offered only by a context
  # that verifies the same way, so a ticket from an unverified connection
  # never stands in for a verified one.
  record SessionTicket,
    server_name : String,
    cipher_suite : CipherSuite,
    resumption_pre_shared_key : Bytes,
    ticket : Bytes,
    ticket_age_add : UInt32,
    received_at : Time::Instant,
    lifetime : Time::Span,
    alpn_protocol : String?,
    certificate_verifier : CertificateVerifier do
    # Returns whether the ticket is still within its lifetime.
    def usable_at?(now : Time::Instant) : Bool
      now - received_at < lifetime
    end

    # The obfuscated ticket age (§4.2.11.1).
    def obfuscated_age(now : Time::Instant) : UInt32
      (now - received_at).total_milliseconds.to_u32!.&+(ticket_age_add)
    end
  end

  # A bounded client cache of session tickets, keyed by server name. Each
  # ticket is taken out when it is offered, so it is used once (RFC 9846
  # §C.4). Safe to share between fibers and threads.
  class SessionCache
    getter largest_server_name_count : Int32
    getter largest_ticket_count_per_name : Int32

    def initialize(@largest_server_name_count : Int32 = 256, @largest_ticket_count_per_name : Int32 = 4)
      @mutex = Mutex.new
      @list_of_tickets_by_name = {} of String => Array(SessionTicket)
    end

    # Stores *ticket*, dropping the oldest name when the cache is full.
    def store(ticket : SessionTicket) : Nil
      @mutex.synchronize do
        list = @list_of_tickets_by_name.delete(ticket.server_name) || [] of SessionTicket
        list << ticket
        list.shift if list.size > @largest_ticket_count_per_name
        @list_of_tickets_by_name[ticket.server_name] = list
        while @list_of_tickets_by_name.size > @largest_server_name_count
          oldest_name = @list_of_tickets_by_name.first_key
          @list_of_tickets_by_name.delete(oldest_name)
        end
      end
    end

    # Takes the newest usable ticket for *server_name*, or nil.
    def take(server_name : String, now : Time::Instant = Time.instant) : SessionTicket?
      @mutex.synchronize do
        list = @list_of_tickets_by_name[server_name]?
        return nil unless list
        list.reject! { |ticket| !ticket.usable_at?(now) }
        ticket = list.pop?
        @list_of_tickets_by_name.delete(server_name) if list.empty?
        ticket
      end
    end

    def size : Int32
      @mutex.synchronize { @list_of_tickets_by_name.sum(&.[1].size) }
    end
  end
end
