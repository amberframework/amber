require "./certified_key"
require "./certificate_verifier"
require "./session_ticket"
require "./limits"
require "./client_verify_mode"

module Amber::Beryl::TLS
  # Whether a client checks the server's certificate chain.
  enum VerifyMode
    # Accept any chain (the CertificateVerify signature is still checked).
    None
    # Verify the chain to the trust store and the name (the default).
    Peer
  end

  # The settings a connection is made with, shaped like
  # `OpenSSL::SSL::Context` so the standard library and Amber can swap it in.
  abstract class Context
    # The cipher suites offered or accepted, in order of preference.
    property list_of_cipher_suites : Array(CipherSuite) = [
      CipherSuite::TLS_AES_128_GCM_SHA256, CipherSuite::TLS_CHACHA20_POLY1305_SHA256, CipherSuite::TLS_AES_256_GCM_SHA384,
    ]
    # The key exchange groups, in order of preference.
    property list_of_groups : Array(NamedGroup) = [NamedGroup::X25519, NamedGroup::Secp256r1]
    # The ALPN protocol names (RFC 7301), in order of preference.
    property list_of_alpn_protocols : Array(String) = [] of String
    property limits : Limits = Limits.new
    # :nodoc:
    #
    # Where random values come from; replaced only by specs.
    property randomness : HandshakeRandomness = HandshakeRandomness.new

    # Sets one ALPN protocol, as `OpenSSL::SSL::Context#alpn_protocol=`.
    def alpn_protocol=(protocol : String) : String
      @list_of_alpn_protocols = [protocol]
      protocol
    end

    # Alias of `list_of_alpn_protocols=`.
    def alpn_protocols=(list_of_protocols : Array(String)) : Array(String)
      @list_of_alpn_protocols = list_of_protocols
    end

    # Client settings.
    #
    # ```
    # context = Amber::Beryl::TLS::Context::Client.new # Mozilla roots, verify the name
    # socket = Amber::Beryl::TLS::Socket::Client.new(tcp_socket, context, hostname: "example.com")
    # ```
    class Client < Context
      property verify_mode : VerifyMode = VerifyMode::Peer
      # The tickets kept for resumption.
      property session_cache : SessionCache = SessionCache.new
      # Whether GREASE values (RFC 8701) are sent.
      property? is_sending_grease : Bool = true
      # Whether the client uses middlebox compatibility mode (RFC 9846
      # Appendix D.4): a session id and a change_cipher_spec record.
      property? is_middlebox_compatible : Bool = true
      # The signature schemes accepted in CertificateVerify, in order.
      property list_of_signature_schemes : Array(SignatureScheme) = [
        SignatureScheme::EcdsaSecp256r1Sha256, SignatureScheme::RsaPssRsaeSha256, SignatureScheme::RsaPssRsaeSha384,
        SignatureScheme::RsaPssRsaeSha512, SignatureScheme::Ed25519, SignatureScheme::EcdsaSecp384r1Sha384,
      ]
      # The groups the first ClientHello carries a key share for.
      property list_of_key_share_groups : Array(NamedGroup) = [NamedGroup::X25519]
      @trust_store : Certificates::TrustStore? = nil
      @certificate_verifier : CertificateVerifier? = nil
      @certified_key : CertifiedKey? = nil
      @list_of_chain_certificates : Array(Certificates::Certificate)? = nil
      @private_key : Certificates::SigningKey? = nil

      # Reads the PEM certificate chain (leaf first) the client presents
      # when a server asks for a certificate, as
      # `OpenSSL::SSL::Context#certificate_chain=`.
      def certificate_chain=(path : String) : String
        @list_of_chain_certificates = Certificates.read_pem_chain(File.read(path))
        @certified_key = nil
        path
      end

      # Reads the PEM private key of the client certificate at *path*
      # (PKCS #8, SEC 1 or PKCS #1), as `OpenSSL::SSL::Context#private_key=`.
      def private_key=(path : String) : String
        @private_key = Certificates.read_private_key(File.read(path))
        @certified_key = nil
        path
      end

      def certified_key=(certified_key : CertifiedKey) : CertifiedKey
        @certified_key = certified_key
      end

      # The chain and key the client presents when a server sends a
      # CertificateRequest, or nil when none is configured (the client
      # then answers with an empty Certificate). Raises `Error` when only
      # the chain or only the key was set.
      def certified_key? : CertifiedKey?
        @certified_key ||= begin
          chain = @list_of_chain_certificates
          key = @private_key
          if chain && key
            CertifiedKey.new(chain, key)
          elsif chain
            raise Error.new("the client context has a certificate chain but no private key")
          elsif key
            raise Error.new("the client context has a private key but no certificate chain")
          end
        end
      end

      # A client that skips certificate verification, as
      # `OpenSSL::SSL::Context::Client.insecure`.
      def self.insecure : Client
        context = new
        context.verify_mode = VerifyMode::None
        context
      end

      # The roots chains are verified to; the pinned Mozilla set unless
      # set.
      def trust_store : Certificates::TrustStore
        @trust_store ||= Certificates::TrustStore.mozilla
      end

      def trust_store=(trust_store : Certificates::TrustStore) : Certificates::TrustStore
        @certificate_verifier = nil
        @trust_store = trust_store
      end

      # Trusts the certificates in the PEM file at *path* instead of the
      # Mozilla roots, as `OpenSSL::SSL::Context#ca_certificates=`.
      def ca_certificates=(path : String) : String
        self.trust_store = Certificates::TrustStore.from_pem(File.read(path))
        path
      end

      # Uses the operating system's bundle of roots.
      def use_system_trust_store : Nil
        self.trust_store = Certificates::TrustStore.system
      end

      # The verifier the handshake uses: set explicitly, or chosen from
      # `verify_mode` and `trust_store`.
      def certificate_verifier : CertificateVerifier
        @certificate_verifier ||= verify_mode.none? ? InsecureVerifier.new : WebPkiVerifier.new(trust_store)
      end

      def certificate_verifier=(verifier : CertificateVerifier) : CertificateVerifier
        @certificate_verifier = verifier
      end

      def verify_mode=(mode : VerifyMode) : VerifyMode
        @certificate_verifier = nil
        @verify_mode = mode
      end
    end

    # Server settings.
    #
    # ```
    # context = Amber::Beryl::TLS::Context::Server.new
    # context.certificate_chain = "chain.pem"
    # context.private_key = "server.key"
    # context.alpn_protocols = ["h2", "http/1.1"]
    # ```
    class Server < Context
      # The ticket lifetime the server states (and enforces).
      property ticket_lifetime : Time::Span = 2.hours
      # The most tickets a server sends after one handshake.
      LARGEST_SESSION_TICKET_COUNT = 16

      # How many tickets the server sends after a full handshake.
      getter session_ticket_count : Int32 = 1
      @certified_key : CertifiedKey? = nil
      @list_of_chain_certificates : Array(Certificates::Certificate)? = nil
      @private_key : Certificates::SigningKey? = nil
      @ticket_key : Bytes

      def initialize
        @ticket_key = Random::Secure.random_bytes(32)
      end

      # Reads the PEM certificate chain (leaf first) at *path*.
      def certificate_chain=(path : String) : String
        @list_of_chain_certificates = Certificates.read_pem_chain(File.read(path))
        @certified_key = nil
        path
      end

      # Reads the PEM private key at *path* (PKCS #8, SEC 1 or PKCS #1).
      def private_key=(path : String) : String
        @private_key = Certificates.read_private_key(File.read(path))
        @certified_key = nil
        path
      end

      def certified_key=(certified_key : CertifiedKey) : CertifiedKey
        @certified_key = certified_key
      end

      # The chain and key the server presents.
      def certified_key : CertifiedKey
        @certified_key ||= begin
          chain = @list_of_chain_certificates || raise Error.new("the server context has no certificate chain")
          key = @private_key || raise Error.new("the server context has no private key")
          CertifiedKey.new(chain, key)
        end
      end

      # The 32-byte key session tickets are sealed under. Random per
      # context; set the same key on several processes to let them resume
      # each other's sessions.
      def ticket_key=(key : Bytes) : Bytes
        raise ArgumentError.new("a ticket key is 32 bytes, not #{key.size}") unless key.size == 32
        @ticket_key = key.dup
      end

      # :nodoc:
      def ticket_key : Bytes
        @ticket_key
      end

      # Sets how many tickets the server sends, from 0 (none) to
      # `LARGEST_SESSION_TICKET_COUNT`.
      def session_ticket_count=(count : Int32) : Int32
        unless 0 <= count <= LARGEST_SESSION_TICKET_COUNT
          raise ArgumentError.new("a session ticket count of #{count}; 0 to #{LARGEST_SESSION_TICKET_COUNT} are allowed")
        end
        @session_ticket_count = count
      end

      # Whether the server sends session tickets.
      def session_tickets_enabled? : Bool
        @session_ticket_count > 0
      end

      # Whether the server asks for a client certificate, and whether one is
      # required. `ClientVerifyMode::None` (the default) sends no
      # CertificateRequest.
      #
      # ```
      # context.client_verify_mode = Amber::Beryl::TLS::ClientVerifyMode::Required
      # context.client_ca_certificates = "clients-ca.pem"
      # ```
      property client_verify_mode : ClientVerifyMode = ClientVerifyMode::None
      # The most bytes of distinguished names a CertificateRequest lists in
      # certificate_authorities (RFC 9846 §4.2.4). A client trust store whose
      # subject names take more is not listed, and the client picks its
      # certificate without the hint.
      property largest_certificate_authorities_bytesize : Int32 = 16_384
      @client_trust_store : Certificates::TrustStore? = nil
      @client_certificate_verifier : CertificateVerifier? = nil

      # Sets the client certificate mode as `OpenSSL::SSL::Context::Server`
      # takes it: `VerifyMode::Peer` requires a client certificate
      # (`ClientVerifyMode::Required`) and `VerifyMode::None` asks for none.
      def verify_mode=(mode : VerifyMode) : VerifyMode
        @client_verify_mode = mode.peer? ? ClientVerifyMode::Required : ClientVerifyMode::None
        mode
      end

      # `VerifyMode::Peer` when the server asks for a client certificate,
      # else `VerifyMode::None`.
      def verify_mode : VerifyMode
        @client_verify_mode.requests_certificate? ? VerifyMode::Peer : VerifyMode::None
      end

      # The roots client chains are verified to. Never defaults to a public
      # root set: a server that asks for client certificates names the
      # authorities it trusts to issue them.
      def client_trust_store : Certificates::TrustStore?
        @client_trust_store
      end

      def client_trust_store=(trust_store : Certificates::TrustStore) : Certificates::TrustStore
        @client_certificate_verifier = nil
        @client_trust_store = trust_store
      end

      # Trusts the certificates in the PEM file at *path* to issue client
      # certificates, as `OpenSSL::SSL::Context#ca_certificates=` does on a
      # server.
      def client_ca_certificates=(path : String) : String
        self.client_trust_store = Certificates::TrustStore.from_pem(File.read(path))
        path
      end

      # The verifier client chains go through: set explicitly, or a
      # `ClientCertificateVerifier` over `client_trust_store`. Raises an
      # `Error` when neither is set.
      def client_certificate_verifier : CertificateVerifier
        @client_certificate_verifier ||= begin
          trust_store = @client_trust_store ||
                        raise Error.new("the server context asks for client certificates but has no client trust store or verifier")
          ClientCertificateVerifier.new(trust_store)
        end
      end

      def client_certificate_verifier=(verifier : CertificateVerifier) : CertificateVerifier
        @client_certificate_verifier = verifier
      end
    end
  end
end
