require "../certificates"

module Amber::Beryl::TLS
  # Decides whether a peer's certificate chain is trusted, and checks the
  # CertificateVerify signature made with its leaf key.
  #
  # `WebPkiVerifier` is the default for clients. `InsecureVerifier` skips
  # the chain (for tests and self-signed development servers) but still
  # checks the signature, so the handshake keeps its integrity against
  # anyone who does not hold the leaf's key.
  abstract class CertificateVerifier
    # The CertificateVerify schemes `verify_with_key` accepts, in the order
    # a server lists them in its CertificateRequest.
    LIST_OF_VERIFIED_SIGNATURE_SCHEMES = [
      SignatureScheme::EcdsaSecp256r1Sha256, SignatureScheme::RsaPssRsaeSha256, SignatureScheme::RsaPssRsaeSha384,
      SignatureScheme::RsaPssRsaeSha512, SignatureScheme::Ed25519, SignatureScheme::EcdsaSecp384r1Sha384,
    ]

    # Raises `CertificateRejected` with the alert to send when *chain*
    # (leaf first) is not trusted for *hostname*.
    abstract def verify_chain(chain : Array(Certificates::Certificate), hostname : String?) : Nil

    # :nodoc:
    #
    # The alert a failed chain verification is reported with (RFC 9846
    # §6.2).
    def self.alert_for(failure : Certificates::VerificationFailed) : AlertDescription
      case failure.reason
      when Certificates::FailureReason::LeafExpiredOrNotYetValid then AlertDescription::CertificateExpired
      when Certificates::FailureReason::NoTrustedPath            then AlertDescription::UnknownCa
      when Certificates::FailureReason::Revoked                  then AlertDescription::CertificateRevoked
      else                                                            AlertDescription::BadCertificate
      end
    end

    # Returns whether *scheme* signs with keys of *leaf*'s type (and, for
    # ECDSA, its curve: TLS 1.3 binds each ECDSA scheme to one curve).
    def self.scheme_fits_key?(leaf : Certificates::Certificate, scheme : SignatureScheme) : Bool
      key = leaf.subject_public_key_info.verification_key
      case scheme
      when SignatureScheme::EcdsaSecp256r1Sha256 then key.is_a?(Crypto::V1::P256::PublicKey)
      when SignatureScheme::EcdsaSecp384r1Sha384 then key.is_a?(Crypto::V1::P384::PublicKey)
      when SignatureScheme::Ed25519              then key.is_a?(Crypto::V1::Ed25519::VerificationKey)
      when SignatureScheme::RsaPssRsaeSha256, SignatureScheme::RsaPssRsaeSha384, SignatureScheme::RsaPssRsaeSha512
        key.is_a?(Crypto::V1::RSA::PublicKey)
      else
        false
      end
    end

    # Returns whether *signature* over *content* verifies under the leaf
    # key of *leaf* with *scheme*.
    def verify_signature(leaf : Certificates::Certificate, scheme : SignatureScheme, content : Bytes, signature : Bytes) : Bool
      key = leaf.subject_public_key_info.verification_key
      return false unless key
      CertificateVerifier.verify_with_key(key, scheme, content, signature)
    end

    # Checks *signature* with *key* under one of the TLS 1.3
    # CertificateVerify schemes Beryl accepts (plan §2); every other
    # scheme, or a key of the wrong type for it, does not verify. A SHA-1
    # scheme raises an `Error` with the illegal_parameter alert, naming
    # SHA-1, before any signature check (RFC 9155 §2).
    def self.verify_with_key(key : Certificates::VerificationKey, scheme : SignatureScheme, content : Bytes, signature : Bytes) : Bool
      if scheme.rsa_pkcs1_sha1? || scheme.ecdsa_sha1?
        raise Error.new("the CertificateVerify is signed with SHA-1 (#{scheme}), which Beryl refuses (RFC 9155)", AlertDescription::IllegalParameter)
      end

      case scheme
      when SignatureScheme::EcdsaSecp256r1Sha256
        key.is_a?(Crypto::V1::P256::PublicKey) && key.verify(content, signature)
      when SignatureScheme::EcdsaSecp384r1Sha384
        key.is_a?(Crypto::V1::P384::PublicKey) && key.verify(content, signature)
      when SignatureScheme::Ed25519
        key.is_a?(Crypto::V1::Ed25519::VerificationKey) && key.verify(content, signature)
      when SignatureScheme::RsaPssRsaeSha256
        key.is_a?(Crypto::V1::RSA::PublicKey) && key.verify_pss_signature(content, signature, hash_function: Crypto::V1::SHA256, salt_bytesize: 32)
      when SignatureScheme::RsaPssRsaeSha384
        key.is_a?(Crypto::V1::RSA::PublicKey) && key.verify_pss_signature(content, signature, hash_function: Crypto::V1::SHA384, salt_bytesize: 48)
      when SignatureScheme::RsaPssRsaeSha512
        key.is_a?(Crypto::V1::RSA::PublicKey) && key.verify_pss_signature(content, signature, hash_function: Crypto::V1::SHA512, salt_bytesize: 64)
      else
        false
      end
    end
  end

  # RFC 5280 path validation to a trust store (B4's `ChainVerification`),
  # the `serverAuth` purpose, the digitalSignature key usage when present,
  # and the RFC 9525 name or IP address check.
  class WebPkiVerifier < CertificateVerifier
    getter trust_store : Certificates::TrustStore

    def initialize(@trust_store : Certificates::TrustStore = Certificates::TrustStore.mozilla, *,
                   @time_source : -> Time = -> { Time.utc })
    end

    def verify_chain(chain : Array(Certificates::Certificate), hostname : String?) : Nil
      leaf = chain.first? || raise CertificateRejected.new("the server sent no certificate", AlertDescription::DecodeError)
      identity = hostname.try do |name|
        Certificates::ServiceIdentity.new(name)
      rescue ArgumentError
        raise CertificateRejected.new("#{name.inspect} is neither a DNS name nor an IP address", AlertDescription::InternalError)
      end
      Certificates::ChainVerification.new(@trust_store).verify(
        leaf, chain[1..],
        identity: identity,
        time: @time_source.call,
        required_key_usage: Certificates::KeyUsage::DigitalSignature,
      )
    rescue failure : Certificates::VerificationFailed
      raise CertificateRejected.new("the certificate chain did not verify: #{failure.message}", CertificateVerifier.alert_for(failure))
    end
  end

  # Verifies a client's certificate chain for a server that asks for one:
  # RFC 5280 path validation to the server's client trust store (B4's
  # `ChainVerification`), the `clientAuth` purpose, and the
  # digitalSignature key usage when present. No name is checked; the
  # application reads the subject from `Socket::Server#peer_certificate`.
  #
  # ```
  # verifier = Amber::Beryl::TLS::ClientCertificateVerifier.new(Amber::Beryl::Certificates::TrustStore.from_pem(File.read("clients-ca.pem")))
  # ```
  class ClientCertificateVerifier < CertificateVerifier
    getter trust_store : Certificates::TrustStore

    def initialize(@trust_store : Certificates::TrustStore, *, @time_source : -> Time = -> { Time.utc })
    end

    # Raises `CertificateRejected` when *chain* does not verify. A client
    # sends no name to check, so *hostname* is ignored.
    def verify_chain(chain : Array(Certificates::Certificate), hostname : String?) : Nil
      leaf = chain.first? || raise CertificateRejected.new("the client sent no certificate", AlertDescription::CertificateRequired)
      Certificates::ChainVerification.new(@trust_store).verify(
        leaf, chain[1..],
        purpose: Certificates::Purpose::ClientAuthentication,
        time: @time_source.call,
        required_key_usage: Certificates::KeyUsage::DigitalSignature,
      )
    rescue failure : Certificates::VerificationFailed
      raise CertificateRejected.new("the client certificate chain did not verify: #{failure.message}", CertificateVerifier.alert_for(failure))
    end
  end

  # Accepts any chain; the CertificateVerify signature is still checked
  # against the leaf key. For tests and development only.
  class InsecureVerifier < CertificateVerifier
    def verify_chain(chain : Array(Certificates::Certificate), hostname : String?) : Nil
      raise CertificateRejected.new("the server sent no certificate", AlertDescription::DecodeError) if chain.empty?
    end
  end
end
