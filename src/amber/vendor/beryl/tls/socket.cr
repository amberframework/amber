require "socket"
require "./client_handshake"
require "./server_handshake"

module Amber::Beryl::TLS
  # A TLS 1.3 connection over another IO, shaped like
  # `OpenSSL::SSL::Socket`: an `IO` with `IO::Buffered`, and the same
  # accessors (`alpn_protocol`, `cipher`, `tls_version`, `hostname`,
  # `peer_certificate`).
  #
  # ```
  # tcp = TCPSocket.new("example.com", 443)
  # tls = Amber::Beryl::TLS::Socket::Client.new(tcp, hostname: "example.com", sync_close: true)
  # tls << "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
  # tls.flush
  # tls.gets_to_end
  # ```
  #
  # Reads and writes may run in two fibers at once (one each). A failure
  # sends the alert the error names before it is raised.
  abstract class Socket < IO
    include IO::Buffered

    # Whether closing this socket closes the IO under it.
    property? sync_close : Bool
    # Whether reads and writes raise a TLS failure as `ConnectionFailed`
    # (an `IO::Error`) instead of the `TLS::Error` itself. A server that
    # treats `IO::Error` as the end of a connection, as `HTTP::Server`
    # does, then ends a failed handshake quietly; `Server` turns it on for
    # the sockets it accepts.
    property? is_raising_io_errors : Bool = false

    @outcome : HandshakeOutcome? = nil
    @read_buffer = Bytes.empty
    @handshake_mutex = Mutex.new
    # Reentrant: a failed write sends its alert while holding the lock.
    @write_mutex = Mutex.new(:reentrant)
    @key_update_times = Deque(Time::Instant).new
    @has_failed = false
    @is_key_update_owed = false
    @are_secrets_wiped = false
    # How many KeyUpdates this end sent.
    getter sent_key_update_count : Int32 = 0

    protected def initialize(@io : IO, @sync_close : Bool, limits : Limits)
      @record_layer = RecordLayer.new(@io, limits)
      @limits = limits
    end

    # The negotiated ALPN protocol, or nil.
    def alpn_protocol : String?
      handshake_outcome.alpn_protocol
    end

    # The IANA name of the negotiated suite, e.g. `TLS_AES_128_GCM_SHA256`.
    def cipher : String
      handshake_outcome.cipher_suite.to_s
    end

    # The negotiated suite.
    def cipher_suite : CipherSuite
      handshake_outcome.cipher_suite
    end

    # Always `"TLSv1.3"`, the string OpenSSL reports.
    def tls_version : String
      "TLSv1.3"
    end

    # Whether the session was resumed from a ticket.
    def resumed? : Bool
      handshake_outcome.resumed?
    end

    # The negotiated key exchange group.
    def group : NamedGroup?
      handshake_outcome.group
    end

    # Returns keying material exported from the connection (RFC 9846
    # §7.5), e.g. for channel binding.
    def export_keying_material(label : String, context : Bytes, bytesize : Int32) : Bytes
      outcome = handshake_outcome
      raise ConnectionClosed.new("the connection's secrets were wiped when it closed", AlertDescription::InternalError) if @are_secrets_wiped
      KeySchedule.export_keying_material(outcome.cipher_suite.hash_algorithm, outcome.exporter_master_secret, label, context, bytesize)
    end

    def local_address
      io = @io
      io.responds_to?(:local_address) ? io.local_address : nil
    end

    def remote_address
      io = @io
      io.responds_to?(:remote_address) ? io.remote_address : nil
    end

    def read_timeout
      io = @io
      io.responds_to?(:read_timeout) ? io.read_timeout : nil
    end

    def read_timeout=(timeout)
      io = @io
      io.read_timeout = timeout if io.responds_to?(:read_timeout=)
    end

    def write_timeout=(timeout)
      io = @io
      io.write_timeout = timeout if io.responds_to?(:write_timeout=)
    end

    # Sends a KeyUpdate and moves to the next sending key (§4.6.3). With
    # *request_peer_update* the peer is asked to update its key too.
    def update_keys(request_peer_update : Bool = false) : Nil
      outcome = handshake_outcome
      @write_mutex.synchronize do
        request = request_peer_update ? KeyUpdateRequest::UpdateRequested : KeyUpdateRequest::UpdateNotRequested
        send_key_update(outcome, request)
        @is_key_update_owed = false
      end
    end

    def unbuffered_read(slice : Bytes) : Int32
      with_io_errors { read_application_data(slice) }
    end

    def unbuffered_write(slice : Bytes) : Nil
      with_io_errors { write_application_data(slice) }
    end

    private def read_application_data(slice : Bytes) : Int32
      handshake_outcome
      raise ConnectionClosed.new("the connection failed earlier", AlertDescription::InternalError) if @has_failed
      return 0 if slice.empty?
      while @read_buffer.empty?
        record = with_alert_on_failure { @record_layer.read_after_handshake }
        return 0 unless record
        content_type, content = record
        if content_type.application_data?
          @read_buffer = content
        else
          with_alert_on_failure { handle_post_handshake_message(content) }
        end
      end
      count = Math.min(slice.size, @read_buffer.size)
      @read_buffer[0, count].copy_to(slice)
      @read_buffer = @read_buffer[count..]
      count
    end

    private def write_application_data(slice : Bytes) : Nil
      outcome = handshake_outcome
      # After a fatal alert either way, nothing more is sent (§6.2).
      raise ConnectionClosed.new("the connection failed earlier", AlertDescription::InternalError) if @has_failed
      @write_mutex.synchronize do
        if @is_key_update_owed || is_key_worn_out?(slice.size)
          with_alert_on_failure { send_key_update(outcome, KeyUpdateRequest::UpdateNotRequested) }
          @is_key_update_owed = false
        end
        with_alert_on_failure { @record_layer.write_application_data(slice) }
      end
    end

    def unbuffered_flush : Nil
      @write_mutex.synchronize { @io.flush }
    end

    # Whether `close` has been called. Reads and writes after it raise
    # `IO::Error` ("Closed stream"), as on any closed IO, and a pool or a
    # driver that checks `closed?` (as `OpenSSL::SSL::Socket` answers it)
    # sees the connection is gone.
    getter? closed : Bool = false

    # Sends close_notify (once the handshake is done), wipes the
    # connection's secrets, then closes the IO below when `sync_close?`.
    # Closing again does nothing.
    def unbuffered_close : Nil
      return if @closed
      @closed = true

      @write_mutex.synchronize do
        @record_layer.write_alert(AlertLevel::Warning, AlertDescription::CloseNotify) if @outcome && !@has_failed
      ensure
        wipe_secrets
      end
    ensure
      @io.close if @sync_close
    end

    def unbuffered_rewind : Nil
      raise IO::Error.new("a TLS socket cannot rewind")
    end

    # The handshake result, running the handshake first when it has not
    # run yet (a server socket made with `accept: false`).
    protected def handshake_outcome : HandshakeOutcome
      if outcome = @outcome
        return outcome
      end
      @handshake_mutex.synchronize do
        if outcome = @outcome
          return outcome
        end
        raise ConnectionClosed.new("the handshake failed earlier", AlertDescription::InternalError) if @has_failed
        outcome = with_handshake_deadline { with_alert_on_failure { run_handshake } }
        @record_layer.largest_outgoing_fragment_bytesize = Math.min(RecordLayer::LARGEST_FRAGMENT_BYTESIZE, (outcome.peer_record_size_limit || 16_385) - 1)
        # Both ends sent record_size_limit, so this end's own limit now holds
        # for what it reads (RFC 8449 §4).
        if outcome.peer_record_size_limit
          @record_layer.largest_incoming_inner_plaintext_bytesize = @limits.record_size_limit
        end
        @outcome = outcome
        outcome
      end
    end

    private abstract def run_handshake : HandshakeOutcome

    # Post-handshake messages: KeyUpdate both ways, NewSessionTicket for
    # a client (§4.6).
    private def handle_post_handshake_message(message : Bytes) : Nil
      handshake_type, body = Messages.unwrap(message)
      case handshake_type
      when HandshakeType::KeyUpdate
        key_update = Messages::KeyUpdate.decode(body)
        record_key_update
        unless @record_layer.handshake_buffer_empty?
          raise TLS::Error.new("a KeyUpdate that does not end its record", AlertDescription::UnexpectedMessage)
        end
        outcome = handshake_outcome
        hash = outcome.cipher_suite.hash_algorithm
        advance_read_secret(outcome, hash)
        # The answer to update_requested is one KeyUpdate before the next
        # application data, however many requests arrive first (§4.6.3).
        if key_update.request.update_requested?
          @write_mutex.synchronize { @is_key_update_owed = true }
        end
      else
        handle_other_post_handshake_message(handshake_type, body)
      end
    end

    private def handle_other_post_handshake_message(handshake_type : HandshakeType?, body : Bytes) : Nil
      raise TLS::Error.new("#{handshake_type || "an unknown handshake message"} after the handshake", AlertDescription::UnexpectedMessage)
    end

    private abstract def advance_read_secret(outcome : HandshakeOutcome, hash : HashAlgorithm) : Nil
    private abstract def send_key_update(outcome : HandshakeOutcome, request : KeyUpdateRequest) : Nil

    # The next traffic secret; the previous one is wiped once the next is
    # derived (§7.2).
    private def next_secret(hash : HashAlgorithm, secret : Bytes) : Bytes
      next_secret = KeySchedule.next_application_traffic_secret(hash, secret)
      Crypto::SecretWiping.wipe(secret)
      next_secret
    end

    private def replace_read_protection(protection : RecordProtection) : Nil
      @record_layer.read_protection.try(&.wipe)
      @record_layer.read_protection = protection
    end

    private def replace_write_protection(protection : RecordProtection) : Nil
      @record_layer.write_protection.try(&.wipe)
      @record_layer.write_protection = protection
    end

    # Whether the sending key would seal more records than
    # `Limits#largest_record_count_per_key` allows were *bytesize* bytes
    # written under it (RFC 9846 §5.5).
    private def is_key_worn_out?(bytesize : Int32) : Bool
      protection = @record_layer.write_protection
      return false unless protection
      record_count = bytesize // @record_layer.largest_outgoing_fragment_bytesize + 1
      protection.sequence_number + record_count > @limits.largest_record_count_per_key
    end

    # Wipes the traffic secrets, the exporter and resumption master
    # secrets and the record keys. Called at close and after a failure,
    # holding the write lock so no record is sealed while its key goes.
    private def wipe_secrets : Nil
      return if @are_secrets_wiped
      @are_secrets_wiped = true
      wipe_traffic_secrets
      if outcome = @outcome
        Crypto::SecretWiping.wipe(outcome.exporter_master_secret)
        Crypto::SecretWiping.wipe(outcome.resumption_master_secret)
      end
      @record_layer.read_protection.try(&.wipe)
      @record_layer.write_protection.try(&.wipe)
    end

    private abstract def wipe_traffic_secrets : Nil

    private def record_key_update : Nil
      now = Time.instant
      @key_update_times << now
      while (oldest = @key_update_times.first?) && now - oldest > 1.minute
        @key_update_times.shift
      end
      if @key_update_times.size > @limits.largest_key_update_count_per_minute
        raise TLS::Error.new("more than #{@limits.largest_key_update_count_per_minute} KeyUpdates in a minute", AlertDescription::UnexpectedMessage)
      end
    end

    # Runs the block; on a failure marks the connection failed, sends the
    # alert a TLS error names and wipes the connection's secrets, all under
    # the write lock: the read path sends alerts too, and two records
    # sealed at once could share a nonce.
    # Raises a TLS failure from the block as `ConnectionFailed` when
    # `is_raising_io_errors?`.
    private def with_io_errors(&)
      yield
    rescue error : TLS::Error
      raise error unless @is_raising_io_errors
      raise ConnectionFailed.new(error)
    end

    private def with_alert_on_failure(&)
      yield
    rescue error : TLS::Error | IO::Error
      @has_failed = true
      @write_mutex.synchronize do
        if error.is_a?(TLS::Error) && !error.is_a?(PeerAlert | HandshakeTimeout | ConnectionClosed)
          @record_layer.write_alert(AlertLevel::Fatal, error.alert_description)
        end
      ensure
        wipe_secrets
      end
      raise error
    end

    # Bounds the whole handshake by `Limits#handshake_timeout` when the
    # IO below is a socket: a watchdog fiber closes the socket at the
    # deadline, so a peer that trickles bytes or stops reading cannot hold
    # the connection open.
    private def with_handshake_deadline(&)
      io = @io
      unless io.is_a?(::Socket)
        return yield
      end
      done = Channel(Nil).new(1)
      has_timed_out = false
      timeout = @limits.handshake_timeout
      spawn do
        select
        when done.receive
        when timeout(timeout)
          has_timed_out = true
          begin
            io.close
          rescue IO::Error
          end
        end
      end
      begin
        yield
      rescue error : IO::Error
        if has_timed_out
          @has_failed = true
          raise HandshakeTimeout.new("the handshake took longer than #{timeout}", AlertDescription::InternalError)
        end
        raise error
      ensure
        done.send(nil) unless has_timed_out
      end
    end

    # The client end. The handshake runs in the constructor.
    class Client < Socket
      getter context : Context::Client
      getter hostname : String?
      @list_of_peer_certificates = [] of Certificates::Certificate
      @client_application_secret = Bytes.empty
      @server_application_secret = Bytes.empty

      # *hostname* is the name (or IP address) the certificate must match
      # and, for a name, the SNI sent.
      def initialize(io : IO, context : Context::Client = Context::Client.new, sync_close : Bool = false, hostname : String? = nil)
        @context = context
        @hostname = hostname
        super(io, sync_close, context.limits)
        begin
          handshake_outcome
        rescue error
          io.close if sync_close
          raise error
        end
      end

      def self.open(io : IO, context : Context::Client = Context::Client.new, sync_close : Bool = false, hostname : String? = nil, &)
        socket = new(io, context, sync_close, hostname)
        begin
          yield socket
        ensure
          socket.close
        end
      end

      # The server's leaf certificate.
      def peer_certificate : Certificates::Certificate?
        handshake_outcome.list_of_peer_certificates.first?
      end

      # The server's chain, as it sent it.
      def peer_certificate_chain : Array(Certificates::Certificate)
        handshake_outcome.list_of_peer_certificates
      end

      private def run_handshake : HandshakeOutcome
        if @context.verify_mode.peer? && @hostname.nil?
          raise TLS::Error.new("a client that verifies the server needs a hostname", AlertDescription::InternalError)
        end
        outcome = ClientHandshake.new(@record_layer, @context, @hostname).perform
        @client_application_secret = outcome.client_application_traffic_secret
        @server_application_secret = outcome.server_application_traffic_secret
        outcome
      end

      private def advance_read_secret(outcome : HandshakeOutcome, hash : HashAlgorithm) : Nil
        @server_application_secret = next_secret(hash, @server_application_secret)
        replace_read_protection(RecordProtection.new(outcome.cipher_suite, @server_application_secret))
      end

      private def send_key_update(outcome : HandshakeOutcome, request : KeyUpdateRequest) : Nil
        @record_layer.write_handshake(Messages::KeyUpdate.new(request).encode)
        @client_application_secret = next_secret(outcome.cipher_suite.hash_algorithm, @client_application_secret)
        replace_write_protection(RecordProtection.new(outcome.cipher_suite, @client_application_secret))
        @sent_key_update_count += 1
        @io.flush
      end

      private def wipe_traffic_secrets : Nil
        Crypto::SecretWiping.wipe(@client_application_secret)
        Crypto::SecretWiping.wipe(@server_application_secret)
      end

      private def handle_other_post_handshake_message(handshake_type : HandshakeType?, body : Bytes) : Nil
        unless handshake_type == HandshakeType::NewSessionTicket
          raise TLS::Error.new("#{handshake_type || "an unknown handshake message"} after the handshake", AlertDescription::UnexpectedMessage)
        end
        ticket = Messages::NewSessionTicket.decode(body)
        if ticket.ticket_lifetime > SealedSessionState::LONGEST_LIFETIME_SECONDS
          raise TLS::Error.new("a ticket lifetime of #{ticket.ticket_lifetime} seconds", AlertDescription::IllegalParameter)
        end
        return if ticket.ticket_lifetime == 0
        hostname = @hostname
        return unless hostname
        outcome = handshake_outcome
        hash = outcome.cipher_suite.hash_algorithm
        @context.session_cache.store(SessionTicket.new(
          hostname, outcome.cipher_suite,
          KeySchedule.resumption_pre_shared_key(hash, outcome.resumption_master_secret, ticket.ticket_nonce),
          ticket.ticket, ticket.ticket_age_add, Time.instant, ticket.ticket_lifetime.seconds, outcome.alpn_protocol,
          @context.certificate_verifier))
      end
    end

    # The server end. With `accept: true` (the default) the handshake runs
    # in the constructor; with `accept: false` it runs on the first read or
    # write, so a server's accept loop never waits on a slow client.
    class Server < Socket
      getter context : Context::Server
      @client_application_secret = Bytes.empty
      @server_application_secret = Bytes.empty

      def initialize(io : IO, context : Context::Server, sync_close : Bool = false, accept : Bool = true)
        @context = context
        super(io, sync_close, context.limits)
        if accept
          begin
            handshake_outcome
          rescue error
            io.close if sync_close
            raise error
          end
        end
      end

      def self.open(io : IO, context : Context::Server, sync_close : Bool = false, &)
        socket = new(io, context, sync_close)
        begin
          yield socket
        ensure
          socket.close
        end
      end

      # Runs the handshake now, as `OpenSSL::SSL::Socket::Server#accept`.
      def accept : Nil
        handshake_outcome
      end

      # The server name the client sent (SNI), or nil.
      def hostname : String?
        handshake_outcome.server_name
      end

      # Beryl's server does not request client certificates.
      def peer_certificate : Certificates::Certificate?
        nil
      end

      private def run_handshake : HandshakeOutcome
        outcome = ServerHandshake.new(@record_layer, @context).perform
        @client_application_secret = outcome.client_application_traffic_secret
        @server_application_secret = outcome.server_application_traffic_secret
        outcome
      end

      private def advance_read_secret(outcome : HandshakeOutcome, hash : HashAlgorithm) : Nil
        @client_application_secret = next_secret(hash, @client_application_secret)
        replace_read_protection(RecordProtection.new(outcome.cipher_suite, @client_application_secret))
      end

      private def send_key_update(outcome : HandshakeOutcome, request : KeyUpdateRequest) : Nil
        @record_layer.write_handshake(Messages::KeyUpdate.new(request).encode)
        @server_application_secret = next_secret(outcome.cipher_suite.hash_algorithm, @server_application_secret)
        replace_write_protection(RecordProtection.new(outcome.cipher_suite, @server_application_secret))
        @sent_key_update_count += 1
        @io.flush
      end

      private def wipe_traffic_secrets : Nil
        Crypto::SecretWiping.wipe(@client_application_secret)
        Crypto::SecretWiping.wipe(@server_application_secret)
      end
    end
  end

  # Wraps a `::Socket::Server` (such as a `TCPServer`) so each accepted
  # connection is a `Socket::Server`, as `OpenSSL::SSL::Server` does.
  # `HTTP::Server#bind(server)` takes it on stock Crystal.
  #
  # ```
  # tcp_server = TCPServer.new("0.0.0.0", 8443)
  # http_server.bind(Amber::Beryl::TLS::Server.new(tcp_server, context))
  # ```
  class Server
    include ::Socket::Server

    getter wrapped : ::Socket::Server
    getter context : Context::Server
    # Whether the handshake runs in `accept`; off by default, so the
    # handshake runs in the connection's own fiber on first use.
    property start_immediately : Bool = false
    property? sync_close : Bool

    def initialize(@wrapped : ::Socket::Server, @context : Context::Server, @sync_close : Bool = true)
    end

    def accept : Socket::Server
      wrap(@wrapped.accept)
    end

    def accept? : Socket::Server?
      if io = @wrapped.accept?
        wrap(io)
      end
    end

    # Sockets accepted here raise TLS failures as `ConnectionFailed` from
    # their reads and writes, so `HTTP::Server` (which ends a connection
    # quietly on an `IO::Error`) never sees an unhandled exception from a
    # client whose handshake fails.
    private def wrap(io : IO) : Socket::Server
      socket = Socket::Server.new(io, @context, sync_close: @sync_close, accept: @start_immediately)
      socket.is_raising_io_errors = true
      socket
    end

    def close : Nil
      wrapped = @wrapped
      wrapped.close if wrapped.responds_to?(:close)
    end

    def local_address : ::Socket::Address
      wrapped = @wrapped
      if wrapped.responds_to?(:local_address)
        wrapped.local_address
      else
        raise TLS::Error.new("the wrapped server has no local address")
      end
    end
  end
end
