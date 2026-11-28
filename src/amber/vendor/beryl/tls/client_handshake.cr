require "./messages/handshake_messages"
require "./messages/extension_codec"
require "./record_layer"
require "./transcript_hash"
require "./context"
require "./handshake_outcome"
require "./handshake_secrets"

module Amber::Beryl::TLS
  # The client side of a TLS 1.3 handshake (RFC 9846 §2, §4), run over a
  # `RecordLayer`. One instance runs one handshake.
  #
  # Order of events: ClientHello; at most one HelloRetryRequest and a
  # second ClientHello; ServerHello; EncryptedExtensions; then either
  # Finished (resumed) or [CertificateRequest] Certificate
  # CertificateVerify Finished; then the client's [Certificate
  # [CertificateVerify]] Finished.
  class ClientHandshake
    alias ExtensionCodec = Messages::ExtensionCodec

    # What the client offered in a ClientHello, kept to check the server's
    # answers against it.
    class Offer
      getter client_hello : Messages::ClientHello
      property message : Bytes
      property list_of_key_exchanges : Array(KeyExchange)
      property session_ticket : SessionTicket?

      def initialize(@client_hello, @message, @list_of_key_exchanges, @session_ticket)
      end
    end

    @transcript = TranscriptHash.new
    @has_sent_change_cipher_spec = false
    @hello_retry_cipher_suite : CipherSuite? = nil
    @secrets = HandshakeSecrets.new

    def initialize(@record_layer : RecordLayer, @context : Context::Client, @hostname : String?)
      @randomness = @context.randomness
    end

    # Runs the handshake.
    def perform : HandshakeOutcome
      offer = build_first_offer
      @record_layer.write_handshake(offer.message, legacy_record_version: ProtocolVersion::TLS_1_0)
      @record_layer.flush
      complete(offer)
    end

    # :nodoc:
    #
    # Runs the handshake from the point where *offer* was sent. `perform`
    # calls it; the RFC 8448 specs call it with the trace's ClientHello.
    #
    # Every secret the handshake derived and does not hand on is wiped when
    # it ends, and on failure the ones it would have handed on too.
    def complete(offer : Offer) : HandshakeOutcome
      offer.session_ticket.try { |ticket| @secrets.held(ticket.resumption_pre_shared_key) }
      outcome = run_handshake(offer)
      @secrets.complete
      outcome
    ensure
      @secrets.wipe
    end

    private def run_handshake(offer : Offer) : HandshakeOutcome
      @transcript.add(offer.message)
      server_hello_message = @record_layer.read_handshake_message
      server_hello = decode_server_hello(server_hello_message)

      if server_hello.hello_retry_request?
        offer = answer_hello_retry_request(offer, server_hello, server_hello_message)
        server_hello_message = @record_layer.read_handshake_message
        server_hello = decode_server_hello(server_hello_message)
        if server_hello.hello_retry_request?
          raise Error.new("a second HelloRetryRequest", AlertDescription::UnexpectedMessage)
        end
      end

      cipher_suite = check_server_hello(offer, server_hello)
      hash = cipher_suite.hash_algorithm
      key_share = ExtensionCodec.decode_server_key_share(server_hello.extension(ExtensionType::KeyShare) || raise Error.new("the ServerHello has no key_share", AlertDescription::MissingExtension))
      key_exchange = offer.list_of_key_exchanges.find { |exchange| exchange.group.value == key_share.group_value }
      raise Error.new("the server's key share is for a group the client sent no share for", AlertDescription::IllegalParameter) unless key_exchange
      shared_secret = @secrets.held(key_exchange.shared_secret(key_share.key_exchange))

      pre_shared_key = nil
      session_ticket = offer.session_ticket
      if selected = server_hello.extension(ExtensionType::PreSharedKey)
        index = ExtensionCodec.decode_selected_identity(selected)
        unless session_ticket && index == 0
          raise Error.new("the server selected PSK identity #{index}, which was not offered", AlertDescription::IllegalParameter)
        end
        unless session_ticket.cipher_suite.hash_algorithm == hash
          raise Error.new("the server resumed with a suite of another hash", AlertDescription::IllegalParameter)
        end
        pre_shared_key = session_ticket.resumption_pre_shared_key
      end
      is_resumed = !pre_shared_key.nil?

      @transcript.add(server_hello_message)
      schedule = @secrets.held(KeySchedule.new(hash, pre_shared_key))
      schedule.enter_handshake_stage(shared_secret)
      Crypto::SecretWiping.wipe(shared_secret)
      handshake_digest = @transcript.digest(hash)
      client_handshake_secret = @secrets.held(schedule.client_handshake_traffic_secret(handshake_digest))
      server_handshake_secret = @secrets.held(schedule.server_handshake_traffic_secret(handshake_digest))
      install_read_protection(RecordProtection.new(cipher_suite, server_handshake_secret))
      # Installed now so that an alert sent while reading the server's
      # flight goes out under the handshake key the server reads with.
      client_handshake_protection = RecordProtection.new(cipher_suite, client_handshake_secret)
      @record_layer.write_protection = client_handshake_protection
      # In compatibility mode the dummy change_cipher_spec goes before the
      # client's first protected record, an alert included (Appendix D.4).
      send_change_cipher_spec_once if offer.client_hello.legacy_session_id.size > 0

      encrypted_extensions_message = read_message(HandshakeType::EncryptedExtensions)
      encrypted_extensions = Messages::EncryptedExtensions.decode(Messages.unwrap(encrypted_extensions_message)[1])
      alpn_protocol, peer_record_size_limit = check_encrypted_extensions(offer, encrypted_extensions)
      @transcript.add(encrypted_extensions_message)

      list_of_peer_certificates = [] of Certificates::Certificate
      certificate_request = nil
      list_of_requested_scheme_values = [] of UInt16
      unless is_resumed
        message = @record_layer.read_handshake_message
        if Messages.unwrap(message)[0] == HandshakeType::CertificateRequest
          certificate_request = Messages::CertificateRequest.decode(Messages.unwrap(message)[1])
          list_of_requested_scheme_values = check_certificate_request(certificate_request)
          @transcript.add(message)
          message = @record_layer.read_handshake_message
        end
        expect_type(message, HandshakeType::Certificate)
        certificate_message = Messages::CertificateMessage.decode(Messages.unwrap(message)[1],
          largest_count: @context.limits.largest_certificate_count,
          largest_bytesize: @context.limits.largest_certificate_chain_bytesize)
        unless certificate_message.certificate_request_context.empty?
          raise Error.new("a server Certificate with a request context", AlertDescription::IllegalParameter)
        end
        if certificate_message.list_of_entries.empty?
          raise Error.new("the server sent an empty Certificate", AlertDescription::DecodeError)
        end
        list_of_peer_certificates = certificate_message.list_of_entries.map do |entry|
          Certificates::Certificate.new(entry.certificate_data)
        rescue error : Certificates::Error
          raise Error.new("a server certificate does not parse: #{error.message}", AlertDescription::BadCertificate)
        end
        check_leaf_entry(certificate_message.list_of_entries.first, list_of_peer_certificates.first)
        @context.certificate_verifier.verify_chain(list_of_peer_certificates, @hostname)
        @transcript.add(message)

        message = read_message(HandshakeType::CertificateVerify)
        certificate_verify = Messages::CertificateVerify.decode(Messages.unwrap(message)[1])
        scheme = SignatureScheme.from_value?(certificate_verify.signature_scheme_value)
        unless scheme && @context.list_of_signature_schemes.includes?(scheme)
          raise Error.new("the server signed with scheme #{certificate_verify.signature_scheme_value}, which was not offered", AlertDescription::IllegalParameter)
        end
        content = Messages::CertificateVerify.signed_content(@transcript.digest(hash), is_server: true)
        unless @context.certificate_verifier.verify_signature(list_of_peer_certificates.first, scheme, content, certificate_verify.signature)
          raise Error.new("the server's CertificateVerify does not verify", AlertDescription::DecryptError)
        end
        @transcript.add(message)
      end

      message = read_message(HandshakeType::Finished)
      finished = Messages::Finished.decode(Messages.unwrap(message)[1], hash.bytesize)
      unless KeySchedule.finished_matches?(hash, server_handshake_secret, @transcript.digest(hash), finished.verify_data)
        raise Error.new("the server's Finished does not verify", AlertDescription::DecryptError)
      end
      @transcript.add(message)

      schedule.enter_master_stage
      application_digest = @transcript.digest(hash)
      client_application_secret = @secrets.handed_on(schedule.client_application_traffic_secret(application_digest))
      server_application_secret = @secrets.handed_on(schedule.server_application_traffic_secret(application_digest))
      exporter_master_secret = @secrets.handed_on(schedule.exporter_master_secret(application_digest))
      install_read_protection(RecordProtection.new(cipher_suite, server_application_secret))

      if certificate_request
        send_client_certificate(certificate_request, list_of_requested_scheme_values, hash)
      end
      client_finished = Messages::Finished.new(KeySchedule.finished_verify_data(hash, client_handshake_secret, @transcript.digest(hash))).encode
      @record_layer.write_handshake(client_finished)
      @transcript.add(client_finished)
      @record_layer.write_protection = RecordProtection.new(cipher_suite, client_application_secret)
      @record_layer.flush
      @record_layer.is_change_cipher_spec_allowed = false

      resumption_master_secret = @secrets.handed_on(schedule.resumption_master_secret(@transcript.digest(hash)))
      @transcript.clear

      HandshakeOutcome.new(cipher_suite, client_application_secret, server_application_secret, exporter_master_secret,
        resumption_master_secret, alpn_protocol, server_name_sent(offer), list_of_peer_certificates, is_resumed,
        peer_record_size_limit, key_exchange.group)
    end

    # Checks a CertificateRequest (§4.3.2) and returns the signature scheme
    # values its signature_algorithms lists. certificate_authorities is
    # read for its form only: the client presents its certificate whatever
    # authorities the server names.
    private def check_certificate_request(certificate_request : Messages::CertificateRequest) : Array(UInt16)
      unless certificate_request.certificate_request_context.empty?
        raise Error.new("a CertificateRequest with a context during the handshake", AlertDescription::IllegalParameter)
      end
      signature_algorithms = certificate_request.extension(ExtensionType::SignatureAlgorithms)
      unless signature_algorithms
        raise Error.new("a CertificateRequest without signature_algorithms", AlertDescription::MissingExtension)
      end
      if certificate_authorities = certificate_request.extension(ExtensionType::CertificateAuthorities)
        ExtensionCodec.decode_certificate_authorities(certificate_authorities)
      end
      ExtensionCodec.decode_u16_list(signature_algorithms)
    end

    # Answers a CertificateRequest (§4.4.2, §4.4.3). With a configured
    # certificate whose key signs one of *list_of_requested_scheme_values*,
    # the client sends its chain and a CertificateVerify over the
    # transcript; otherwise an empty Certificate tells the server it has
    # none, and the server decides (§4.4.2.4). Both enter the transcript
    # before the client's Finished.
    private def send_client_certificate(certificate_request : Messages::CertificateRequest,
                                        list_of_requested_scheme_values : Array(UInt16), hash : HashAlgorithm) : Nil
      request_context = certificate_request.certificate_request_context
      certified_key = @context.certified_key?
      scheme = certified_key ? certified_key.signature_scheme_for(list_of_requested_scheme_values) : nil
      unless certified_key && scheme
        write_and_record(Messages::CertificateMessage.new(request_context, [] of Messages::CertificateEntry).encode)
        return
      end

      list_of_entries = certified_key.list_of_certificates.map do |certificate|
        Messages::CertificateEntry.new(certificate.encoded, [] of Messages::Extension)
      end
      write_and_record(Messages::CertificateMessage.new(request_context, list_of_entries).encode)
      content = Messages::CertificateVerify.signed_content(@transcript.digest(hash), is_server: false)
      signature = certified_key.sign(scheme, content, @randomness)
      write_and_record(Messages::CertificateVerify.new(scheme.value, signature).encode)
    end

    private def write_and_record(message : Bytes) : Nil
      @record_layer.write_handshake(message)
      @transcript.add(message)
    end

    # The leaf's CertificateEntry may carry only extensions the client
    # asked for, and Beryl's client asks for none (status_request and
    # signed_certificate_timestamp are not offered, §4.4.2). A leaf whose
    # key usage leaves out digitalSignature cannot sign CertificateVerify
    # (§4.4.2.2), whatever the certificate verifier decides.
    private def check_leaf_entry(entry : Messages::CertificateEntry, leaf : Certificates::Certificate) : Nil
      if extension = entry.list_of_extensions.first?
        raise Error.new("the extension #{extension.type_value} on the server's certificate, which the client did not ask for", AlertDescription::UnsupportedExtension)
      end
      if (key_usage = leaf.key_usage) && !key_usage.digital_signature?
        raise Error.new("the server certificate's key usage leaves out digitalSignature", AlertDescription::BadCertificate)
      end
    end

    private def server_name_sent(offer : Offer) : String?
      offer.client_hello.extension(ExtensionType::ServerName).try { |contents| ExtensionCodec.decode_server_name(contents) }
    end

    private def read_message(expected : HandshakeType) : Bytes
      message = @record_layer.read_handshake_message
      expect_type(message, expected)
      message
    end

    private def expect_type(message : Bytes, expected : HandshakeType) : Nil
      actual = Messages.unwrap(message)[0]
      unless actual == expected
        raise Error.new("#{actual || "an unknown handshake message"} arrived where #{expected} was expected", AlertDescription::UnexpectedMessage)
      end
    end

    private def install_read_protection(protection : RecordProtection) : Nil
      unless @record_layer.handshake_buffer_empty?
        raise Error.new("a handshake message straddles a key change", AlertDescription::UnexpectedMessage)
      end
      @record_layer.read_protection = protection
    end

    private def send_change_cipher_spec_once : Nil
      return if @has_sent_change_cipher_spec
      @record_layer.write_change_cipher_spec
      @has_sent_change_cipher_spec = true
    end

    private def decode_server_hello(message : Bytes) : Messages::ServerHello
      expect_type(message, HandshakeType::ServerHello)
      Messages::ServerHello.decode(Messages.unwrap(message)[1])
    end

    # The checks every ServerHello and HelloRetryRequest must pass
    # (§4.1.3, §4.1.4). Returns the selected suite.
    private def check_server_hello(offer : Offer, server_hello : Messages::ServerHello) : CipherSuite
      version_contents = server_hello.extension(ExtensionType::SupportedVersions)
      unless version_contents && ExtensionCodec.decode_selected_version(version_contents) == ProtocolVersion::TLS_1_3
        raise Error.new("the server did not select TLS 1.3", AlertDescription::ProtocolVersion)
      end
      unless server_hello.legacy_version == ProtocolVersion::TLS_1_2
        raise Error.new("a ServerHello with legacy_version #{server_hello.legacy_version}", AlertDescription::ProtocolVersion)
      end
      unless server_hello.legacy_session_id_echo == offer.client_hello.legacy_session_id
        raise Error.new("the server did not echo the session id", AlertDescription::IllegalParameter)
      end
      raise Error.new("a ServerHello with compression", AlertDescription::IllegalParameter) unless server_hello.legacy_compression_method == 0
      cipher_suite = CipherSuite.from_value?(server_hello.cipher_suite)
      unless cipher_suite && @context.list_of_cipher_suites.includes?(cipher_suite)
        raise Error.new("the server selected suite #{server_hello.cipher_suite}, which was not offered", AlertDescription::IllegalParameter)
      end
      if hello_retry_suite = @hello_retry_cipher_suite
        unless hello_retry_suite == cipher_suite
          raise Error.new("the ServerHello's suite differs from the HelloRetryRequest's", AlertDescription::IllegalParameter)
        end
      end
      allowed = server_hello.hello_retry_request? ? {ExtensionType::KeyShare, ExtensionType::Cookie, ExtensionType::SupportedVersions} : {ExtensionType::KeyShare, ExtensionType::PreSharedKey, ExtensionType::SupportedVersions}
      server_hello.list_of_extensions.each do |extension|
        type = extension.type?
        unless type && allowed.includes?(type)
          raise Error.new("the extension #{extension.type_value} in a #{server_hello.hello_retry_request? ? "HelloRetryRequest" : "ServerHello"}", AlertDescription::UnsupportedExtension)
        end
        unless offer.client_hello.has_extension?(type) || type.cookie?
          raise Error.new("the server sent #{type}, which the client did not offer", AlertDescription::UnsupportedExtension)
        end
      end
      # The downgrade sentinels (§4.1.3) mean a TLS 1.2 or older answer;
      # a TLS 1.3 ServerHello never carries them.
      tail = server_hello.random[24, 8]
      if tail == "DOWNGRD\x01".to_slice || tail == "DOWNGRD\x00".to_slice
        raise Error.new("a TLS 1.3 ServerHello carries a downgrade sentinel", AlertDescription::IllegalParameter)
      end
      cipher_suite
    end

    private def answer_hello_retry_request(offer : Offer, hello_retry_request : Messages::ServerHello, message : Bytes) : Offer
      # The server waits for the second ClientHello, so its
      # HelloRetryRequest ends its record.
      unless @record_layer.handshake_buffer_empty?
        raise Error.new("data after the HelloRetryRequest in its record", AlertDescription::UnexpectedMessage)
      end
      cipher_suite = check_server_hello(offer, hello_retry_request)
      @hello_retry_cipher_suite = cipher_suite
      selected_group = hello_retry_request.extension(ExtensionType::KeyShare).try { |contents| ExtensionCodec.decode_selected_group(contents) }
      cookie = hello_retry_request.extension(ExtensionType::Cookie).try { |contents| ExtensionCodec.decode_cookie(contents) }
      if selected_group
        group = NamedGroup.from_value?(selected_group)
        unless group && @context.list_of_groups.includes?(group)
          raise Error.new("the HelloRetryRequest asks for group #{selected_group}, which was not offered", AlertDescription::IllegalParameter)
        end
        if offer.list_of_key_exchanges.any? { |exchange| exchange.group == group }
          raise Error.new("the HelloRetryRequest asks for a group the client already sent a share for", AlertDescription::IllegalParameter)
        end
      elsif cookie.nil?
        raise Error.new("a HelloRetryRequest that would not change the ClientHello", AlertDescription::IllegalParameter)
      end

      hash = cipher_suite.hash_algorithm
      @transcript.replace_with_message_hash(hash)
      @transcript.add(message)

      list_of_key_exchanges = selected_group ? [KeyExchange.generate(NamedGroup.new(selected_group), @randomness)] : offer.list_of_key_exchanges
      session_ticket = offer.session_ticket
      session_ticket = nil if session_ticket && session_ticket.cipher_suite.hash_algorithm != hash

      list_of_extensions = [] of Messages::Extension
      offer.client_hello.list_of_extensions.each do |extension|
        case extension.type?
        when ExtensionType::KeyShare
          # Without a selected group the key_share is sent again unchanged,
          # its GREASE entry included (§4.1.2).
          list_of_extensions << if selected_group
            Messages::Extension.new(extension.type_value, ExtensionCodec.encode_client_key_shares(
              list_of_key_exchanges.map { |exchange| ExtensionCodec::KeyShareEntry.new(exchange.group.value, exchange.public_key_bytes) }))
          else
            extension
          end
          list_of_extensions << Messages::Extension.new(ExtensionType::Cookie.value, ExtensionCodec.encode_cookie(cookie)) if cookie
        when ExtensionType::PreSharedKey, ExtensionType::EarlyData
          # Rebuilt below, or dropped.
        else
          list_of_extensions << extension
        end
      end
      client_hello = Messages::ClientHello.new(offer.client_hello.random, offer.client_hello.legacy_session_id,
        offer.client_hello.list_of_cipher_suites, list_of_extensions)
      second_offer = Offer.new(client_hello, Bytes.empty, list_of_key_exchanges, session_ticket)
      second_offer.message = encode_with_binder(client_hello, session_ticket)

      send_change_cipher_spec_once if client_hello.legacy_session_id.size > 0
      @record_layer.write_handshake(second_offer.message)
      @record_layer.flush
      @transcript.add(second_offer.message)
      second_offer
    end

    private def build_first_offer : Offer
      random = @randomness.random_bytes(32)
      session_id = @context.is_middlebox_compatible? ? @randomness.random_bytes(32) : Bytes.empty
      grease = @context.is_sending_grease? ? grease_values : nil
      list_of_suites = @context.list_of_cipher_suites.map(&.value)
      list_of_suites.unshift(grease[0]) if grease

      list_of_key_exchanges = @context.list_of_key_share_groups.select { |group| @context.list_of_groups.includes?(group) }
        .map { |group| KeyExchange.generate(group, @randomness) }
      list_of_extensions = [] of Messages::Extension
      list_of_extensions << Messages::Extension.new(grease[1], Bytes.empty) if grease
      if (hostname = @hostname) && Certificates::ServiceIdentity.parse_ip_address(hostname).nil?
        sni = hostname.ends_with?('.') ? hostname[0, hostname.size - 1] : hostname
        list_of_extensions << Messages::Extension.new(ExtensionType::ServerName.value, ExtensionCodec.encode_server_name(sni))
      end
      list_of_groups = @context.list_of_groups.map(&.value)
      list_of_groups.unshift(grease[2]) if grease
      list_of_extensions << Messages::Extension.new(ExtensionType::SupportedGroups.value, ExtensionCodec.encode_u16_list(list_of_groups))
      list_of_schemes = @context.list_of_signature_schemes.map(&.value)
      list_of_extensions << Messages::Extension.new(ExtensionType::SignatureAlgorithms.value, ExtensionCodec.encode_u16_list(list_of_schemes))
      list_of_certificate_schemes = list_of_schemes + [SignatureScheme::RsaPkcs1Sha256, SignatureScheme::RsaPkcs1Sha384, SignatureScheme::RsaPkcs1Sha512].map(&.value)
      list_of_extensions << Messages::Extension.new(ExtensionType::SignatureAlgorithmsCert.value, ExtensionCodec.encode_u16_list(list_of_certificate_schemes))
      list_of_shares = list_of_key_exchanges.map { |exchange| ExtensionCodec::KeyShareEntry.new(exchange.group.value, exchange.public_key_bytes) }
      list_of_shares.unshift(ExtensionCodec::KeyShareEntry.new(grease[2], Bytes[0])) if grease
      list_of_extensions << Messages::Extension.new(ExtensionType::KeyShare.value, ExtensionCodec.encode_client_key_shares(list_of_shares))
      list_of_versions = [ProtocolVersion::TLS_1_3]
      list_of_versions.unshift(grease[3]) if grease
      list_of_extensions << Messages::Extension.new(ExtensionType::SupportedVersions.value, ExtensionCodec.encode_client_supported_versions(list_of_versions))
      list_of_extensions << Messages::Extension.new(ExtensionType::PskKeyExchangeModes.value, ExtensionCodec.encode_psk_modes(Bytes[PskKeyExchangeMode::PskDheKe.value]))
      # This end's own limit on the records it reads (RFC 8449).
      list_of_extensions << Messages::Extension.new(ExtensionType::RecordSizeLimit.value, ExtensionCodec.encode_record_size_limit(@context.limits.record_size_limit))
      unless @context.list_of_alpn_protocols.empty?
        list_of_extensions << Messages::Extension.new(ExtensionType::ApplicationLayerProtocolNegotiation.value, ExtensionCodec.encode_protocol_names(@context.list_of_alpn_protocols))
      end
      list_of_extensions << Messages::Extension.new(grease[4], Bytes[0]) if grease

      session_ticket = take_session_ticket
      client_hello = Messages::ClientHello.new(random, session_id, list_of_suites, list_of_extensions)
      offer = Offer.new(client_hello, Bytes.empty, list_of_key_exchanges, session_ticket)
      offer.message = encode_with_binder(client_hello, session_ticket)
      offer
    end

    private def take_session_ticket : SessionTicket?
      hostname = @hostname
      return nil unless hostname
      ticket = @context.session_cache.take(hostname)
      return nil unless ticket
      return nil unless @context.list_of_cipher_suites.any? { |suite| suite.hash_algorithm == ticket.cipher_suite.hash_algorithm }
      # Resumption skips certificate checks, so a ticket is used only by a
      # context that would have verified its server the same way.
      return nil unless ticket.certificate_verifier.same?(@context.certificate_verifier)
      ticket
    end

    # Encodes *client_hello*, appending the pre_shared_key extension with
    # its binder when *session_ticket* is offered (§4.2.11.2). The binder
    # covers the transcript so far and this ClientHello up to its binders.
    private def encode_with_binder(client_hello : Messages::ClientHello, session_ticket : SessionTicket?) : Bytes
      return client_hello.encode unless session_ticket
      hash = session_ticket.cipher_suite.hash_algorithm
      identity = ExtensionCodec::PskIdentity.new(session_ticket.ticket, session_ticket.obfuscated_age(Time.instant))
      placeholder = Bytes.new(hash.bytesize)
      client_hello.list_of_extensions << Messages::Extension.new(ExtensionType::PreSharedKey.value,
        ExtensionCodec.encode_client_pre_shared_key([identity], [placeholder]))
      message = client_hello.encode
      prefix = message[0, Messages::ClientHello.binder_prefix_bytesize(message, [placeholder])]
      schedule = KeySchedule.new(hash, session_ticket.resumption_pre_shared_key)
      binder_key = schedule.resumption_binder_key
      binder = KeySchedule.finished_verify_data(hash, binder_key, @transcript.digest_with(prefix, hash))
      Crypto::SecretWiping.wipe(binder_key)
      schedule.wipe
      binder.copy_to(message + (message.size - binder.size))
      client_hello.list_of_extensions[-1] = Messages::Extension.new(ExtensionType::PreSharedKey.value,
        ExtensionCodec.encode_client_pre_shared_key([identity], [binder]))
      message
    end

    # Five distinct GREASE values (RFC 8701 §2): 0x?A?A with a random
    # nibble.
    private def grease_values : Array(UInt16)
      list_of_values = [] of UInt16
      random = @randomness.random_bytes(16)
      random.each do |byte|
        nibble = (byte & 0x0F).to_u16
        value = (nibble << 12) | 0x0A00_u16 | (nibble << 4) | 0x000A_u16
        list_of_values << value unless list_of_values.includes?(value)
        break if list_of_values.size == 5
      end
      while list_of_values.size < 5
        candidate = ((list_of_values.size.to_u16 + 1) * 0x1010_u16) | 0x0A0A_u16
        list_of_values << candidate unless list_of_values.includes?(candidate)
      end
      list_of_values
    end

    # Checks EncryptedExtensions against the offer (§4.3.1). Returns the
    # ALPN protocol and the server's record size limit.
    private def check_encrypted_extensions(offer : Offer, encrypted_extensions : Messages::EncryptedExtensions) : {String?, Int32?}
      alpn_protocol = nil
      record_size_limit = nil
      encrypted_extensions.list_of_extensions.each do |extension|
        type = extension.type?
        # An extension the client did not offer is refused first, whatever
        # its type (§4.2); one it offered but that has no place here is an
        # illegal_parameter below.
        unless type && offer.client_hello.has_extension?(type)
          raise Error.new("the server sent extension #{extension.type_value}, which the client did not offer", AlertDescription::UnsupportedExtension)
        end
        case type
        when ExtensionType::ServerName
          raise Error.new("a server_name acknowledgement with contents", AlertDescription::DecodeError) unless extension.contents.empty?
        when ExtensionType::SupportedGroups
          ExtensionCodec.decode_u16_list(extension.contents)
        when ExtensionType::ApplicationLayerProtocolNegotiation
          list_of_names = ExtensionCodec.decode_protocol_names(extension.contents)
          unless list_of_names.size == 1 && @context.list_of_alpn_protocols.includes?(list_of_names.first)
            raise Error.new("the server selected an ALPN protocol that was not offered", AlertDescription::IllegalParameter)
          end
          alpn_protocol = list_of_names.first
        when ExtensionType::RecordSizeLimit
          record_size_limit = ExtensionCodec.decode_record_size_limit(extension.contents)
        when ExtensionType::KeyShare, ExtensionType::PreSharedKey, ExtensionType::SupportedVersions, ExtensionType::Cookie,
             ExtensionType::PskKeyExchangeModes, ExtensionType::SignatureAlgorithms, ExtensionType::SignatureAlgorithmsCert,
             ExtensionType::CertificateAuthorities, ExtensionType::OidFilters, ExtensionType::PostHandshakeAuth
          raise Error.new("#{type} in EncryptedExtensions", AlertDescription::IllegalParameter)
        end
      end
      {alpn_protocol, record_size_limit}
    end
  end
end
