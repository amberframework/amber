require "./messages/handshake_messages"
require "./messages/extension_codec"
require "./record_layer"
require "./transcript_hash"
require "./context"
require "./handshake_outcome"
require "./handshake_secrets"

module Amber::Beryl::TLS
  # The server side of a TLS 1.3 handshake (RFC 9846 §2, §4), run over a
  # `RecordLayer`. One instance runs one handshake.
  #
  # Beryl's server authenticates with its certificate (or a resumption
  # PSK with a fresh ECDHE exchange), never requests a client certificate,
  # never accepts 0-RTT data, and sends at most one HelloRetryRequest.
  class ServerHandshake
    alias ExtensionCodec = Messages::ExtensionCodec

    # The choices made from one ClientHello.
    private record Selection,
      cipher_suite : CipherSuite,
      group : NamedGroup,
      client_key_share : Bytes?,
      alpn_protocol : String?,
      server_name : String?,
      peer_record_size_limit : Int32?

    @transcript = TranscriptHash.new
    @has_sent_change_cipher_spec = false
    @secrets = HandshakeSecrets.new

    def initialize(@record_layer : RecordLayer, @context : Context::Server)
      @randomness = @context.randomness
    end

    # Runs the handshake. Every secret it derived and does not hand on is
    # wiped when it ends, and on failure the ones it would have handed on
    # too.
    def perform : HandshakeOutcome
      outcome = run_handshake
      @secrets.complete
      outcome
    ensure
      @secrets.wipe
    end

    private def run_handshake : HandshakeOutcome
      # The compatibility change_cipher_spec may come only after the first
      # ClientHello (RFC 9846 §5).
      @record_layer.is_change_cipher_spec_allowed = false
      client_hello_message = @record_layer.read_handshake_message
      @record_layer.is_change_cipher_spec_allowed = true
      expect_type(client_hello_message, HandshakeType::ClientHello)
      client_hello = Messages::ClientHello.decode(Messages.unwrap(client_hello_message)[1])
      check_client_hello(client_hello)
      selection = select_parameters(client_hello, nil)
      refuse_early_data(client_hello, after_hello_retry_request: false)

      unless selection.client_key_share
        # No share for the group the server wants: one HelloRetryRequest
        # (§4.1.4). The client waits for it, so the first ClientHello ends
        # its record.
        unless @record_layer.handshake_buffer_empty?
          raise Error.new("data after the first ClientHello in its record", AlertDescription::UnexpectedMessage)
        end
        @transcript.add(client_hello_message)
        @transcript.replace_with_message_hash(selection.cipher_suite.hash_algorithm)
        hello_retry_request = Messages::ServerHello.new(Messages::HELLO_RETRY_REQUEST_RANDOM, client_hello.legacy_session_id,
          selection.cipher_suite.value, [
          Messages::Extension.new(ExtensionType::KeyShare.value, ExtensionCodec.encode_selected_group(selection.group.value)),
          Messages::Extension.new(ExtensionType::SupportedVersions.value, ExtensionCodec.encode_selected_version(ProtocolVersion::TLS_1_3)),
        ]).encode
        @record_layer.write_handshake(hello_retry_request)
        send_change_cipher_spec_once if client_hello.legacy_session_id.size > 0
        @record_layer.flush
        @transcript.add(hello_retry_request)
        refuse_early_data(client_hello, after_hello_retry_request: true)

        second_message = @record_layer.read_handshake_message
        expect_type(second_message, HandshakeType::ClientHello)
        second_hello = Messages::ClientHello.decode(Messages.unwrap(second_message)[1])
        check_client_hello(second_hello)
        check_second_client_hello(client_hello, second_hello)
        second_selection = select_parameters(second_hello, selection)
        unless second_selection.client_key_share && second_selection.group == selection.group && second_selection.cipher_suite == selection.cipher_suite
          raise Error.new("the second ClientHello does not answer the HelloRetryRequest", AlertDescription::IllegalParameter)
        end
        client_hello, client_hello_message, selection = second_hello, second_message, second_selection
        @record_layer.is_skipping_plaintext_early_data = false
        @record_layer.early_data_skip_budget = 0
      end

      hash = selection.cipher_suite.hash_algorithm
      resumed_state, selected_identity = find_resumable_session(client_hello, client_hello_message, selection)
      # The CertificateVerify scheme is chosen before the ServerHello, so a
      # client that offers none of this key's schemes is refused in the clear.
      certificate_scheme = nil
      unless resumed_state
        list_of_offered_schemes = client_hello.extension(ExtensionType::SignatureAlgorithms).try { |contents| ExtensionCodec.decode_u16_list(contents) } || [] of UInt16
        certificate_scheme = @context.certified_key.signature_scheme_for(list_of_offered_schemes) ||
                             raise Error.new("the client offers no signature scheme this server's key signs", AlertDescription::HandshakeFailure)
      end
      @transcript.add(client_hello_message)

      key_exchange = KeyExchange.generate(selection.group, @randomness)
      shared_secret = @secrets.held(key_exchange.shared_secret(selection.client_key_share || raise Error.new("no client key share")))
      list_of_server_hello_extensions = [
        Messages::Extension.new(ExtensionType::KeyShare.value, ExtensionCodec.encode_server_key_share(
          ExtensionCodec::KeyShareEntry.new(selection.group.value, key_exchange.public_key_bytes))),
      ]
      if selected_identity
        list_of_server_hello_extensions << Messages::Extension.new(ExtensionType::PreSharedKey.value, ExtensionCodec.encode_selected_identity(selected_identity))
      end
      list_of_server_hello_extensions << Messages::Extension.new(ExtensionType::SupportedVersions.value, ExtensionCodec.encode_selected_version(ProtocolVersion::TLS_1_3))
      server_hello = Messages::ServerHello.new(@randomness.random_bytes(32), client_hello.legacy_session_id,
        selection.cipher_suite.value, list_of_server_hello_extensions).encode
      @record_layer.write_handshake(server_hello)
      send_change_cipher_spec_once if client_hello.legacy_session_id.size > 0
      @transcript.add(server_hello)

      schedule = @secrets.held(KeySchedule.new(hash, resumed_state.try(&.resumption_pre_shared_key)))
      resumed_state.try { |state| @secrets.held(state.resumption_pre_shared_key) }
      schedule.enter_handshake_stage(shared_secret)
      Crypto::SecretWiping.wipe(shared_secret)
      handshake_digest = @transcript.digest(hash)
      client_handshake_secret = @secrets.held(schedule.client_handshake_traffic_secret(handshake_digest))
      server_handshake_secret = @secrets.held(schedule.server_handshake_traffic_secret(handshake_digest))
      @record_layer.write_protection = RecordProtection.new(selection.cipher_suite, server_handshake_secret)

      list_of_encrypted_extensions = [] of Messages::Extension
      if selection.server_name && resumed_state.nil?
        list_of_encrypted_extensions << Messages::Extension.new(ExtensionType::ServerName.value, Bytes.empty)
      end
      if alpn_protocol = selection.alpn_protocol
        list_of_encrypted_extensions << Messages::Extension.new(ExtensionType::ApplicationLayerProtocolNegotiation.value,
          ExtensionCodec.encode_protocol_names([alpn_protocol]))
      end
      if selection.peer_record_size_limit
        list_of_encrypted_extensions << Messages::Extension.new(ExtensionType::RecordSizeLimit.value,
          ExtensionCodec.encode_record_size_limit(@context.limits.record_size_limit))
      end
      write_and_record(Messages::EncryptedExtensions.new(list_of_encrypted_extensions).encode)

      if scheme = certificate_scheme
        certified_key = @context.certified_key
        entries = certified_key.list_of_certificates.map { |certificate| Messages::CertificateEntry.new(certificate.encoded, [] of Messages::Extension) }
        write_and_record(Messages::CertificateMessage.new(Bytes.empty, entries).encode)
        content = Messages::CertificateVerify.signed_content(@transcript.digest(hash), is_server: true)
        signature = certified_key.sign(scheme, content, @randomness)
        write_and_record(Messages::CertificateVerify.new(scheme.value, signature).encode)
      end
      write_and_record(Messages::Finished.new(KeySchedule.finished_verify_data(hash, server_handshake_secret, @transcript.digest(hash))).encode)

      schedule.enter_master_stage
      application_digest = @transcript.digest(hash)
      client_application_secret = @secrets.handed_on(schedule.client_application_traffic_secret(application_digest))
      server_application_secret = @secrets.handed_on(schedule.server_application_traffic_secret(application_digest))
      exporter_master_secret = @secrets.handed_on(schedule.exporter_master_secret(application_digest))
      @record_layer.write_protection = RecordProtection.new(selection.cipher_suite, server_application_secret)
      @record_layer.flush

      install_read_protection(RecordProtection.new(selection.cipher_suite, client_handshake_secret))
      @record_layer.is_accepting_plaintext_alerts = true
      finished_message = @record_layer.read_handshake_message
      @record_layer.is_accepting_plaintext_alerts = false
      expect_type(finished_message, HandshakeType::Finished)
      finished = Messages::Finished.decode(Messages.unwrap(finished_message)[1], hash.bytesize)
      unless KeySchedule.finished_matches?(hash, client_handshake_secret, @transcript.digest(hash), finished.verify_data)
        raise Error.new("the client's Finished does not verify", AlertDescription::DecryptError)
      end
      @transcript.add(finished_message)
      install_read_protection(RecordProtection.new(selection.cipher_suite, client_application_secret))
      @record_layer.is_change_cipher_spec_allowed = false
      @record_layer.early_data_skip_budget = 0

      resumption_master_secret = @secrets.handed_on(schedule.resumption_master_secret(@transcript.digest(hash)))
      @transcript.clear

      outcome = HandshakeOutcome.new(selection.cipher_suite, client_application_secret, server_application_secret,
        exporter_master_secret, resumption_master_secret, selection.alpn_protocol, selection.server_name,
        [] of Certificates::Certificate, !resumed_state.nil?, selection.peer_record_size_limit, selection.group)
      send_session_tickets(client_hello, outcome)
      outcome
    end

    private def write_and_record(message : Bytes) : Nil
      @record_layer.write_handshake(message)
      @transcript.add(message)
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

    # The checks on any ClientHello (§4.1.2, §4.2, §9.2).
    private def check_client_hello(client_hello : Messages::ClientHello) : Nil
      # SSL 3.0 and older are never negotiated (Appendix D.5), so such a
      # legacy_version is no TLS 1.3 ClientHello.
      if client_hello.legacy_version < ProtocolVersion::TLS_1_0
        raise Error.new("a ClientHello with legacy_version #{client_hello.legacy_version}", AlertDescription::ProtocolVersion)
      end
      versions_contents = client_hello.extension(ExtensionType::SupportedVersions)
      unless versions_contents && ExtensionCodec.decode_client_supported_versions(versions_contents).includes?(ProtocolVersion::TLS_1_3)
        raise Error.new("the client does not offer TLS 1.3", AlertDescription::ProtocolVersion)
      end
      unless client_hello.legacy_compression_methods == Bytes[0]
        raise Error.new("a TLS 1.3 ClientHello with compression methods other than null", AlertDescription::IllegalParameter)
      end
      list_of_extensions = client_hello.list_of_extensions
      list_of_extensions.each_with_index do |extension, index|
        if extension.type_value == ExtensionType::PreSharedKey.value && index != list_of_extensions.size - 1
          raise Error.new("pre_shared_key is not the last extension", AlertDescription::IllegalParameter)
        end
      end
      has_key_share = client_hello.has_extension?(ExtensionType::KeyShare)
      has_groups = client_hello.has_extension?(ExtensionType::SupportedGroups)
      if has_key_share != has_groups
        raise Error.new("key_share and supported_groups must come together", AlertDescription::MissingExtension)
      end
      if client_hello.has_extension?(ExtensionType::PreSharedKey) && !client_hello.has_extension?(ExtensionType::PskKeyExchangeModes)
        raise Error.new("pre_shared_key without psk_key_exchange_modes", AlertDescription::MissingExtension)
      end
      if !client_hello.has_extension?(ExtensionType::PreSharedKey) && !client_hello.has_extension?(ExtensionType::SignatureAlgorithms)
        raise Error.new("no signature_algorithms", AlertDescription::MissingExtension)
      end
      raise Error.new("no key_share: Beryl requires (EC)DHE", AlertDescription::MissingExtension) unless has_key_share
      # Decoding checks each list's structure.
      client_hello.extension(ExtensionType::SignatureAlgorithms).try { |contents| ExtensionCodec.decode_u16_list(contents) }
      client_hello.extension(ExtensionType::SignatureAlgorithmsCert).try { |contents| ExtensionCodec.decode_u16_list(contents) }
      client_hello.extension(ExtensionType::PskKeyExchangeModes).try { |contents| ExtensionCodec.decode_psk_modes(contents) }
      client_hello.extension(ExtensionType::ServerName).try { |contents| ExtensionCodec.decode_server_name(contents) }
    end

    # The second ClientHello must be the first with the changes §4.1.2
    # allows: a new key share, the cookie, no early_data, new binders.
    private def check_second_client_hello(first : Messages::ClientHello, second : Messages::ClientHello) : Nil
      unless first.random == second.random && first.legacy_session_id == second.legacy_session_id &&
             first.list_of_cipher_suites == second.list_of_cipher_suites
        raise Error.new("the second ClientHello changes more than the HelloRetryRequest allows", AlertDescription::IllegalParameter)
      end
      if second.has_extension?(ExtensionType::EarlyData)
        raise Error.new("early_data in the second ClientHello", AlertDescription::IllegalParameter)
      end
      if second.has_extension?(ExtensionType::Cookie)
        raise Error.new("a cookie the server did not send", AlertDescription::IllegalParameter)
      end
      unless first.legacy_version == second.legacy_version && first.legacy_compression_methods == second.legacy_compression_methods
        raise Error.new("the second ClientHello changes more than the HelloRetryRequest allows", AlertDescription::IllegalParameter)
      end
      # The same extensions in the same order and with the same contents,
      # apart from the changes §4.1.2 allows: a new key_share, pre_shared_key
      # recomputed or dropped, early_data dropped, padding resized.
      unless comparable_extensions(first) == comparable_extensions(second)
        raise Error.new("the second ClientHello changes its extensions beyond what the HelloRetryRequest allows", AlertDescription::IllegalParameter)
      end
    end

    private def comparable_extensions(client_hello : Messages::ClientHello) : Array({UInt16, Bytes})
      list = [] of {UInt16, Bytes}
      client_hello.list_of_extensions.each do |extension|
        case extension.type?
        when ExtensionType::PreSharedKey, ExtensionType::EarlyData, ExtensionType::Padding
          next
        when ExtensionType::KeyShare
          list << {extension.type_value, Bytes.empty}
        else
          list << {extension.type_value, extension.contents}
        end
      end
      list
    end

    # The suite, group, ALPN and name from *client_hello*. When
    # *previous* is given (the second ClientHello), its suite and group
    # are kept.
    private def select_parameters(client_hello : Messages::ClientHello, previous : Selection?) : Selection
      cipher_suite = if previous
                       previous.cipher_suite
                     else
                       @context.list_of_cipher_suites.find { |suite| client_hello.list_of_cipher_suites.includes?(suite.value) } ||
                         raise Error.new("no cipher suite in common", AlertDescription::HandshakeFailure)
                     end
      unless client_hello.list_of_cipher_suites.includes?(cipher_suite.value)
        raise Error.new("the second ClientHello drops the selected suite", AlertDescription::IllegalParameter)
      end

      list_of_client_groups = ExtensionCodec.decode_u16_list(client_hello.extension(ExtensionType::SupportedGroups) || Bytes.empty)
      # A set, so every share is checked against the groups in linear time.
      client_group_values = list_of_client_groups.to_set
      list_of_shares = ExtensionCodec.decode_client_key_shares(client_hello.extension(ExtensionType::KeyShare) || Bytes.empty)
      list_of_shares.each do |share|
        unless client_group_values.includes?(share.group_value)
          raise Error.new("a key share for group #{share.group_value}, which supported_groups does not list", AlertDescription::IllegalParameter)
        end
      end
      group, share = if previous
                       entry = list_of_shares.find { |candidate| candidate.group_value == previous.group.value }
                       unless entry && list_of_shares.size == 1
                         raise Error.new("the second ClientHello must carry one share, for #{previous.group}", AlertDescription::IllegalParameter)
                       end
                       {previous.group, entry.key_exchange}
                     else
                       shared_group = @context.list_of_groups.find { |candidate| list_of_shares.any? { |entry| entry.group_value == candidate.value } }
                       if shared_group
                         {shared_group, list_of_shares.find! { |entry| entry.group_value == shared_group.value }.key_exchange}
                       else
                         wanted = @context.list_of_groups.find { |candidate| list_of_client_groups.includes?(candidate.value) } ||
                                  raise Error.new("no key exchange group in common", AlertDescription::HandshakeFailure)
                         {wanted, nil}
                       end
                     end

      alpn_protocol = nil
      if contents = client_hello.extension(ExtensionType::ApplicationLayerProtocolNegotiation)
        list_of_offered = ExtensionCodec.decode_protocol_names(contents)
        unless @context.list_of_alpn_protocols.empty?
          alpn_protocol = @context.list_of_alpn_protocols.find { |protocol| list_of_offered.includes?(protocol) } ||
                          raise Error.new("no ALPN protocol in common", AlertDescription::NoApplicationProtocol)
        end
      end
      server_name = client_hello.extension(ExtensionType::ServerName).try { |contents| ExtensionCodec.decode_server_name(contents) }
      record_size_limit = client_hello.extension(ExtensionType::RecordSizeLimit).try { |contents| ExtensionCodec.decode_record_size_limit(contents) }
      if limit = record_size_limit
        @record_layer.largest_outgoing_fragment_bytesize = Math.min(RecordLayer::LARGEST_FRAGMENT_BYTESIZE, limit - 1)
      end
      Selection.new(cipher_suite, group, share, alpn_protocol, server_name, record_size_limit)
    end

    # Beryl never accepts 0-RTT. A client that sent early_data has its
    # early records skipped, within the budget (§4.2.10).
    private def refuse_early_data(client_hello : Messages::ClientHello, *, after_hello_retry_request : Bool) : Nil
      return unless client_hello.has_extension?(ExtensionType::EarlyData)
      @record_layer.early_data_skip_budget = @context.limits.largest_skipped_early_data_bytesize
      @record_layer.is_skipping_plaintext_early_data = after_hello_retry_request
    end

    # Returns the state of the first offered ticket this server sealed and
    # can resume with, and its index; or nils for a full handshake. A
    # binder that does not verify ends the handshake (§4.2.11).
    private def find_resumable_session(client_hello : Messages::ClientHello, message : Bytes, selection : Selection) : {SealedSessionState?, Int32?}
      contents = client_hello.extension(ExtensionType::PreSharedKey)
      return {nil, nil} unless contents
      list_of_identities, list_of_binders = ExtensionCodec.decode_client_pre_shared_key(contents)
      modes = ExtensionCodec.decode_psk_modes(client_hello.extension(ExtensionType::PskKeyExchangeModes) || Bytes.empty)
      return {nil, nil} unless modes.includes?(PskKeyExchangeMode::PskDheKe.value)

      hash = selection.cipher_suite.hash_algorithm
      now_milliseconds = Time.utc.to_unix_ms
      list_of_identities.each_with_index do |identity, index|
        state = SealedSessionState.open(identity.identity, @context.ticket_key)
        next unless state
        next unless state.cipher_suite.hash_algorithm == hash
        # A ticket from the future (another process's clock, or a forged
        # issue time under a shared key) is never resumed.
        age_milliseconds = now_milliseconds - state.issued_at_unix_milliseconds
        next unless 0 <= age_milliseconds < state.lifetime_seconds.to_i64 * 1000
        next unless state.server_name == selection.server_name
        binder = list_of_binders[index]
        next unless binder.size == hash.bytesize
        prefix = message[0, Messages::ClientHello.binder_prefix_bytesize(message, list_of_binders)]
        schedule = KeySchedule.new(hash, state.resumption_pre_shared_key)
        binder_key = schedule.resumption_binder_key
        is_binder_valid = KeySchedule.finished_matches?(hash, binder_key, @transcript.digest_with(prefix, hash), binder)
        Crypto::SecretWiping.wipe(binder_key)
        schedule.wipe
        raise Error.new("a PSK binder does not verify", AlertDescription::DecryptError) unless is_binder_valid
        return {state, index}
      end
      {nil, nil}
    end

    private def send_session_tickets(client_hello : Messages::ClientHello, outcome : HandshakeOutcome) : Nil
      return unless @context.session_tickets_enabled?
      modes = client_hello.extension(ExtensionType::PskKeyExchangeModes).try { |contents| ExtensionCodec.decode_psk_modes(contents) }
      return unless modes && modes.includes?(PskKeyExchangeMode::PskDheKe.value)
      hash = outcome.cipher_suite.hash_algorithm
      lifetime = Math.min(@context.ticket_lifetime.total_seconds.to_u32, SealedSessionState::LONGEST_LIFETIME_SECONDS)
      @context.session_ticket_count.times do |count|
        nonce = Bytes[count.to_u8]
        pre_shared_key = KeySchedule.resumption_pre_shared_key(hash, outcome.resumption_master_secret, nonce)
        age_add = IO::ByteFormat::BigEndian.decode(UInt32, @randomness.random_bytes(4))
        state = SealedSessionState.new(outcome.cipher_suite, pre_shared_key, Time.utc.to_unix_ms, lifetime, age_add,
          outcome.alpn_protocol, outcome.server_name)
        ticket = state.seal(@context.ticket_key)
        Crypto::SecretWiping.wipe(pre_shared_key)
        @record_layer.write_handshake(Messages::NewSessionTicket.new(lifetime, age_add, nonce, ticket).encode)
      end
      @record_layer.flush
    end
  end
end
