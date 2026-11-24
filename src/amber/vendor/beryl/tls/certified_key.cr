require "../certificates"
require "./handshake_randomness"

module Amber::Beryl::TLS
  # A certificate chain and the private key of its leaf: what a server
  # presents and signs its CertificateVerify with.
  #
  # ```
  # certified_key = Amber::Beryl::TLS::CertifiedKey.from_pem(File.read("chain.pem"), File.read("server.key"))
  # ```
  #
  # Keys: P-256 (signs `ecdsa_secp256r1_sha256`), RSA 2,048 to 4,096 bits
  # (`rsa_pss_rsae_sha256/384/512`), Ed25519 (`ed25519`).
  class CertifiedKey
    getter list_of_certificates : Array(Certificates::Certificate)
    getter private_key : Certificates::SigningKey

    def initialize(@list_of_certificates : Array(Certificates::Certificate), @private_key : Certificates::SigningKey)
      raise ArgumentError.new("a certified key needs at least its leaf certificate") if @list_of_certificates.empty?
    end

    # Reads the chain (leaf first) and the key from PEM text.
    def self.from_pem(chain_pem : String, private_key_pem : String) : CertifiedKey
      new(Certificates.read_pem_chain(chain_pem), Certificates.read_private_key(private_key_pem))
    end

    # The signature schemes this key signs, in Beryl's order of preference.
    def list_of_signature_schemes : Array(SignatureScheme)
      key = @private_key
      if key.is_a?(Crypto::V1::P256::PrivateKey)
        [SignatureScheme::EcdsaSecp256r1Sha256]
      elsif key.is_a?(Crypto::V1::Ed25519::SigningKey)
        [SignatureScheme::Ed25519]
      else
        [SignatureScheme::RsaPssRsaeSha256, SignatureScheme::RsaPssRsaeSha384, SignatureScheme::RsaPssRsaeSha512]
      end
    end

    # Returns the first scheme of this key that the peer offered, or nil.
    def signature_scheme_for(list_of_offered_values : Array(UInt16)) : SignatureScheme?
      list_of_signature_schemes.find { |scheme| list_of_offered_values.includes?(scheme.value) }
    end

    # Signs *content* (the CertificateVerify input) with *scheme*, which
    # must be one of `list_of_signature_schemes`. RSA-PSS draws its salt
    # (one hash long, RFC 9846 §4.2.3) from *randomness*.
    def sign(scheme : SignatureScheme, content : Bytes, randomness : HandshakeRandomness) : Bytes
      key = @private_key
      if key.is_a?(Crypto::V1::P256::PrivateKey) && scheme.ecdsa_secp256r1_sha256?
        key.sign(content)
      elsif key.is_a?(Crypto::V1::Ed25519::SigningKey) && scheme.ed25519?
        key.sign(content)
      elsif key.is_a?(Crypto::V1::RSA::PrivateKey)
        case scheme
        when SignatureScheme::RsaPssRsaeSha256
          key.sign_with_pss_using_salt(content, randomness.random_bytes(32), hash_function: Crypto::V1::SHA256)
        when SignatureScheme::RsaPssRsaeSha384
          key.sign_with_pss_using_salt(content, randomness.random_bytes(48), hash_function: Crypto::V1::SHA384)
        when SignatureScheme::RsaPssRsaeSha512
          key.sign_with_pss_using_salt(content, randomness.random_bytes(64), hash_function: Crypto::V1::SHA512)
        else
          raise Error.new("an RSA key cannot sign #{scheme}", AlertDescription::InternalError)
        end
      else
        raise Error.new("this key cannot sign #{scheme}", AlertDescription::InternalError)
      end
    end
  end
end
