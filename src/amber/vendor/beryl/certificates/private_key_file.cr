require "../crypto"
require "../crypto/secret_wiping"
require "./subject_public_key"

module Amber::Beryl::Certificates
  # The private key types a key file can hold that Beryl signs with.
  alias SigningKey = Crypto::V1::RSA::PrivateKey | Crypto::V1::P256::PrivateKey | Crypto::V1::Ed25519::SigningKey

  # Reads private keys from the files TLS servers are configured with:
  # PKCS #8 (`PRIVATE KEY`, RFC 5958), SEC 1 (`EC PRIVATE KEY`, RFC 5915)
  # and PKCS #1 (`RSA PRIVATE KEY`, RFC 8017 Appendix A.1.2), in PEM or DER.
  #
  # ```
  # key = Amber::Beryl::Certificates::PrivateKeyFile.read_pem(File.read("server.key"))
  # ```
  #
  # Keys: RSA with two primes, 2,048 to 4,096 bits; P-256; Ed25519.
  # Encrypted PKCS #8 files are not read. The DER Beryl decodes from PEM is
  # wiped once the key is built; the caller owns, and should wipe, the text
  # or bytes it hands in. The lengths in a key's DER are public (they are
  # in the file's size), so reading them is not a secret-dependent branch
  # beyond what the file already shows.
  module PrivateKeyFile
    alias DER = Encoding::DER

    # Reads the first private key block in the PEM *text*.
    def self.read_pem(text : String) : SigningKey
      block = Encoding::PEM.decode_blocks(text).find { |candidate| {"PRIVATE KEY", "EC PRIVATE KEY", "RSA PRIVATE KEY"}.includes?(candidate.label) }
      raise MalformedCertificate.new("no PRIVATE KEY, EC PRIVATE KEY or RSA PRIVATE KEY block") unless block

      begin
        case block.label
        when "EC PRIVATE KEY"  then read_elliptic_curve_der(block.bytes)
        when "RSA PRIVATE KEY" then read_rsa_der(block.bytes)
        else                        read_der(block.bytes)
        end
      ensure
        Crypto::SecretWiping.wipe(block.bytes)
      end
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the key file is malformed: #{error.message}")
    end

    # Reads a DER PKCS #8 PrivateKeyInfo (RFC 5958 OneAsymmetricKey).
    def self.read_der(bytes : Bytes) : SigningKey
      reader = DER::Reader.new(bytes)
      key = reader.read_sequence do |info|
        version = info.read_small_integer
        raise UnsupportedKey.new("PKCS #8 version #{version}") unless version == 0 || version == 1
        algorithm, parameters = info.read_sequence do |identifier|
          {identifier.read_object_identifier, identifier.at_end? ? nil : identifier.read_element}
        end
        private_key = info.read_octet_string
        # Attributes [0] and the public key [1] (version 2) are skipped.
        until info.at_end?
          info.read_element
        end

        case algorithm
        when ObjectIdentifiers::RSA_ENCRYPTION
          read_rsa_der(private_key)
        when ObjectIdentifiers::ELLIPTIC_CURVE_PUBLIC_KEY
          raise UnsupportedKey.new("an EC key without a named curve") unless parameters && parameters.tag == DER::OBJECT_IDENTIFIER
          read_elliptic_curve_der(private_key, DER::ObjectIdentifier.new(parameters.content))
        when ObjectIdentifiers::ED25519
          raise UnsupportedKey.new("an Ed25519 key with algorithm parameters") if parameters
          seed = DER::Reader.new(private_key).read_octet_string
          raise UnsupportedKey.new("an Ed25519 key of #{seed.size} bytes") unless seed.size == Crypto::V1::Ed25519::SEED_BYTESIZE
          Crypto::V1::Ed25519::SigningKey.new(seed)
        else
          raise UnsupportedKey.new("the key algorithm #{algorithm}")
        end
      end
      reader.finish
      key
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the PKCS #8 key is malformed: #{error.message}")
    rescue error : Crypto::Error
      raise UnsupportedKey.new("the key is refused: #{error.message}")
    end

    # Reads a DER ECPrivateKey (RFC 5915). *curve* is the curve the
    # enclosing PKCS #8 names; a SEC 1 file names it itself.
    def self.read_elliptic_curve_der(bytes : Bytes, curve : DER::ObjectIdentifier? = nil) : SigningKey
      reader = DER::Reader.new(bytes)
      key = reader.read_sequence do |sequence|
        version = sequence.read_small_integer
        raise UnsupportedKey.new("ECPrivateKey version #{version}") unless version == 1
        scalar = sequence.read_octet_string
        named_curve = curve
        if parameters = sequence.read_optional_element(DER::Tag.context_specific(0, is_constructed: true))
          inner_curve = sequence.enter(parameters, &.read_object_identifier)
          raise UnsupportedKey.new("the key names two different curves") if named_curve && named_curve != inner_curve
          named_curve = inner_curve
        end
        sequence.read_optional_element(DER::Tag.context_specific(1, is_constructed: true))
        raise UnsupportedKey.new("an EC key without a named curve") unless named_curve
        raise UnsupportedKey.new("the curve #{named_curve}; Beryl signs with P-256") unless named_curve == ObjectIdentifiers::SECP256R1
        Crypto::V1::P256::PrivateKey.new(scalar)
      end
      reader.finish
      key
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the EC key is malformed: #{error.message}")
    rescue error : Crypto::Error
      raise UnsupportedKey.new("the key is refused: #{error.message}")
    end

    # Reads a DER RSAPrivateKey (RFC 8017 Appendix A.1.2), two primes only.
    def self.read_rsa_der(bytes : Bytes) : SigningKey
      reader = DER::Reader.new(bytes)
      key = reader.read_sequence do |sequence|
        version = sequence.read_small_integer
        raise UnsupportedKey.new("an RSA key with more than two primes") unless version == 0
        Crypto::V1::RSA::PrivateKey.new(
          modulus: sequence.read_unsigned_integer_bytes,
          public_exponent: sequence.read_unsigned_integer_bytes,
          private_exponent: sequence.read_unsigned_integer_bytes,
          first_prime: sequence.read_unsigned_integer_bytes,
          second_prime: sequence.read_unsigned_integer_bytes,
          first_prime_exponent: sequence.read_unsigned_integer_bytes,
          second_prime_exponent: sequence.read_unsigned_integer_bytes,
          coefficient: sequence.read_unsigned_integer_bytes,
        )
      end
      reader.finish
      key
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the RSA key is malformed: #{error.message}")
    rescue error : Crypto::Error
      raise UnsupportedKey.new("the key is refused: #{error.message}")
    end
  end
end
