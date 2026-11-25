require "random/secure"
require "../crypto"

module Amber::Beryl::TLS
  # Where a handshake gets its random values: the hello randoms, session
  # ids, ephemeral keys, PSS salts, ticket nonces and ages, GREASE values.
  #
  # Every value comes from `Random::Secure`. The class is open so that the
  # specs can replay the fixed values of RFC 8448; applications never set
  # it.
  class HandshakeRandomness
    # Returns *bytesize* random bytes.
    def random_bytes(bytesize : Int32) : Bytes
      Random::Secure.random_bytes(bytesize)
    end

    # Returns a new X25519 key.
    def generate_x25519_key : Crypto::V1::X25519::PrivateKey
      Crypto::V1::X25519::PrivateKey.generate
    end

    # Returns a new P-256 key.
    def generate_p256_key : Crypto::V1::P256::PrivateKey
      Crypto::V1::P256::PrivateKey.generate
    end
  end

  # One side of an ephemeral (EC)DHE exchange on a supported group.
  abstract class KeyExchange
    getter group : NamedGroup

    def initialize(@group : NamedGroup)
    end

    # Returns a fresh exchange on *group*.
    def self.generate(group : NamedGroup, randomness : HandshakeRandomness) : KeyExchange
      case group
      when NamedGroup::X25519    then X25519Exchange.new(randomness.generate_x25519_key)
      when NamedGroup::Secp256r1 then Secp256r1Exchange.new(randomness.generate_p256_key)
      else
        raise Error.new("no key exchange on #{group}", AlertDescription::InternalError)
      end
    end

    # The public key as it goes in a key_share entry.
    abstract def public_key_bytes : Bytes

    # Returns the shared secret with the peer's *peer_key_exchange*, or
    # raises `illegal_parameter` for a key that is malformed or of small
    # order (§4.2.8.2, RFC 7748 §6.1).
    abstract def shared_secret(peer_key_exchange : Bytes) : Bytes
  end

  # X25519 (RFC 7748).
  class X25519Exchange < KeyExchange
    def initialize(@private_key : Crypto::V1::X25519::PrivateKey)
      super(NamedGroup::X25519)
    end

    def public_key_bytes : Bytes
      @private_key.public_key.to_slice
    end

    def shared_secret(peer_key_exchange : Bytes) : Bytes
      raise Error.new("an X25519 share of #{peer_key_exchange.size} bytes", AlertDescription::IllegalParameter) unless peer_key_exchange.size == 32
      @private_key.shared_secret(Crypto::V1::X25519::PublicKey.new(peer_key_exchange)) ||
        raise Error.new("an X25519 share of small order", AlertDescription::IllegalParameter)
    end
  end

  # secp256r1 with uncompressed points (§4.2.8.2).
  class Secp256r1Exchange < KeyExchange
    def initialize(@private_key : Crypto::V1::P256::PrivateKey)
      super(NamedGroup::Secp256r1)
    end

    def public_key_bytes : Bytes
      @private_key.public_key.to_uncompressed
    end

    def shared_secret(peer_key_exchange : Bytes) : Bytes
      unless peer_key_exchange.size == 65 && peer_key_exchange[0] == 4
        raise Error.new("a secp256r1 share that is not an uncompressed point", AlertDescription::IllegalParameter)
      end
      peer = begin
        Crypto::V1::P256::PublicKey.new(peer_key_exchange)
      rescue error : Crypto::Error
        raise Error.new("a secp256r1 share off the curve: #{error.message}", AlertDescription::IllegalParameter)
      end
      @private_key.shared_secret(peer)
    end
  end
end
