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
    # Raises `CertificateRejected` with the alert to send when *chain*
    # (leaf first) is not trusted for *hostname*.
    abstract def verify_chain(chain : Array(Certificates::Certificate), hostname : String?) : Nil

    # Returns whether *signature* over *content* verifies under the leaf
    # key of *leaf* with *scheme*.
    def verify_signature(leaf : Certificates::Certificate, scheme : SignatureScheme, content : Bytes, signature : Bytes) : Bool
      key = leaf.subject_public_key_info.verification_key
      return false unless key
      CertificateVerifier.verify_with_key(key, scheme, content, signature)
    end

    # Checks *signature* with *key* under one of the TLS 1.3
    # CertificateVerify schemes Beryl accepts (plan §2); every other
    # scheme, or a key of the wrong type for it, does not verify.
    def self.verify_with_key(key : Certificates::VerificationKey, scheme : SignatureScheme, content : Bytes, signature : Bytes) : Bool
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
      description = case failure.reason
                    when Certificates::FailureReason::LeafExpiredOrNotYetValid then AlertDescription::CertificateExpired
                    when Certificates::FailureReason::NoTrustedPath            then AlertDescription::UnknownCa
                    when Certificates::FailureReason::Revoked                  then AlertDescription::CertificateRevoked
                    else                                                            AlertDescription::BadCertificate
                    end
      raise CertificateRejected.new("the certificate chain did not verify: #{failure.message}", description)
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
