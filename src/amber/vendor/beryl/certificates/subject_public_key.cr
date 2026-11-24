require "../crypto"
require "./object_identifiers"
require "./error"

module Amber::Beryl::Certificates
  # The public key types a certificate can carry that Beryl verifies with.
  alias VerificationKey = Crypto::V1::RSA::PublicKey | Crypto::V1::P256::PublicKey | Crypto::V1::P384::PublicKey | Crypto::V1::Ed25519::VerificationKey

  # A SubjectPublicKeyInfo (RFC 5280 §4.1.2.7): an algorithm identifier and
  # the key bytes.
  #
  # Reading one checks only its DER structure, as OpenSSL's `d2i_X509` and
  # Go's parser do. `verification_key` decodes the key the first time it is
  # asked for and returns `nil` for a key Beryl does not use, with the
  # reason in `unusable_key_reason`:
  #
  # - RSA (`rsaEncryption` with NULL parameters): a modulus of 2,048 to
  #   8,192 bits whose size is a multiple of 8 (CA/Browser Forum baseline
  #   requirements §6.1.5), an odd public exponent from 3 to 2^32 - 1;
  # - EC (`id-ecPublicKey`): the named curves P-256 and P-384 (RFC 5480);
  #   explicit curve parameters are refused (baseline requirements §7.1.3.1.2);
  # - Ed25519 (RFC 8410), with absent parameters.
  class SubjectPublicKeyInfo
    getter algorithm : Encoding::DER::ObjectIdentifier
    # The algorithm parameters element, when present.
    getter parameters : Encoding::DER::Element?
    # The contents of the subjectPublicKey BIT STRING.
    getter key_bytes : Bytes
    # The whole SubjectPublicKeyInfo encoding.
    getter encoded : Bytes

    @verification_key : VerificationKey? = nil
    @unusable_key_reason : String? = nil
    @is_decoded = false

    def initialize(@algorithm, @parameters, @key_bytes, @encoded)
    end

    # Reads a SubjectPublicKeyInfo from *reader*.
    def self.read(reader : Encoding::DER::Reader) : SubjectPublicKeyInfo
      element = reader.read_element(Encoding::DER::SEQUENCE)
      reader.enter(element) do |sequence|
        algorithm, parameters = sequence.read_sequence do |identifier|
          oid = identifier.read_object_identifier
          parameter_element = identifier.at_end? ? nil : identifier.read_element
          identifier.check_universal_contents(parameter_element) if parameter_element
          {oid, parameter_element}
        end
        key_bytes = sequence.read_byte_aligned_bit_string
        SubjectPublicKeyInfo.new(algorithm, parameters, key_bytes, element.encoded)
      end
    end

    # Reads a DER SubjectPublicKeyInfo on its own, as a `PUBLIC KEY` PEM
    # block or Wycheproof's `publicKeyDer` holds it.
    def self.from_der(bytes : Bytes) : SubjectPublicKeyInfo
      reader = Encoding::DER::Reader.new(bytes)
      public_key_info = read(reader)
      reader.finish
      public_key_info
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the SubjectPublicKeyInfo is malformed: #{error.message}")
    end

    # The key, decoded, or `nil` when Beryl does not use it.
    def verification_key : VerificationKey?
      decode_once
      @verification_key
    end

    # Why `verification_key` is `nil`, or `nil` when it is not.
    def unusable_key_reason : String?
      decode_once
      @unusable_key_reason
    end

    private def decode_once : Nil
      return if @is_decoded

      @is_decoded = true
      @verification_key = decode_verification_key
    rescue error : Crypto::Error | Encoding::Error | MalformedCertificate
      @unusable_key_reason = error.message
    end

    private def decode_verification_key : VerificationKey?
      parameters = @parameters
      case @algorithm
      when ObjectIdentifiers::RSA_ENCRYPTION
        unless parameters && parameters.tag == Encoding::DER::NULL && parameters.content.empty?
          return unusable("an RSA key's algorithm parameters must be NULL (RFC 3279 §2.3.1)")
        end
        modulus, exponent = SubjectPublicKeyInfo.read_rsa_public_key(@key_bytes)
        key = Crypto::V1::RSA::PublicKey.new(modulus, exponent)
        unless key.modulus_bit_count % 8 == 0
          return unusable("an RSA modulus of #{key.modulus_bit_count} bits is not a multiple of 8")
        end
        key
      when ObjectIdentifiers::ELLIPTIC_CURVE_PUBLIC_KEY
        unless parameters && parameters.tag == Encoding::DER::OBJECT_IDENTIFIER
          return unusable("an EC key must name its curve (RFC 5480 §2.1.1); explicit parameters are refused")
        end
        Encoding::DER.check_object_identifier(parameters)
        curve = Encoding::DER::ObjectIdentifier.new(parameters.content)
        case curve
        when ObjectIdentifiers::SECP256R1 then Crypto::V1::P256::PublicKey.new(@key_bytes)
        when ObjectIdentifiers::SECP384R1 then Crypto::V1::P384::PublicKey.new(@key_bytes)
        else                                   unusable("the curve #{curve} is not one Beryl verifies with (P-256, P-384)")
        end
      when ObjectIdentifiers::ED25519
        return unusable("an Ed25519 key has no algorithm parameters (RFC 8410 §3)") if parameters
        Crypto::V1::Ed25519::VerificationKey.new(@key_bytes)
      else
        unusable("the key algorithm #{@algorithm} is not one Beryl verifies with")
      end
    end

    private def unusable(reason : String) : Nil
      @unusable_key_reason = reason
      nil
    end

    # :nodoc:
    #
    # Reads RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent
    # INTEGER } (RFC 8017 Appendix A.1.1) and returns both magnitudes.
    def self.read_rsa_public_key(bytes : Bytes) : {Bytes, Bytes}
      reader = Encoding::DER::Reader.new(bytes)
      components = reader.read_sequence do |sequence|
        {sequence.read_unsigned_integer_bytes, sequence.read_unsigned_integer_bytes}
      end
      reader.finish
      components
    end
  end

  # A signature algorithm identifier (RFC 5280 §4.1.1.2) and what it means
  # for verification.
  struct SignatureAlgorithm
    # The signature schemes Beryl verifies.
    enum Scheme
      RsaPkcs1
      RsaPss
      Ecdsa
      Ed25519
      # An algorithm Beryl does not verify: SHA-1 or MD5 signatures, DSA,
      # ML-DSA, or a known algorithm with parameters it refuses.
      Unsupported
    end

    # The hash each scheme is used with.
    enum HashFunction
      None
      Sha256
      Sha384
      Sha512
    end

    getter scheme : Scheme
    getter hash_function : HashFunction
    # The whole AlgorithmIdentifier encoding, which RFC 5280 §4.1.1.2
    # requires to equal the one inside the signed part.
    getter encoded : Bytes
    getter identifier : Encoding::DER::ObjectIdentifier

    def initialize(@scheme, @hash_function, @encoded, @identifier)
    end

    # Reads an AlgorithmIdentifier from *reader*.
    def self.read(reader : Encoding::DER::Reader) : SignatureAlgorithm
      element = reader.read_element(Encoding::DER::SEQUENCE)
      reader.enter(element) do |sequence|
        identifier = sequence.read_object_identifier
        parameters = sequence.at_end? ? nil : sequence.read_element
        scheme, hash = classify(identifier, parameters, sequence)
        SignatureAlgorithm.new(scheme, hash, element.encoded, identifier)
      end
    end

    private def self.classify(identifier, parameters : Encoding::DER::Element?, reader : Encoding::DER::Reader) : {Scheme, HashFunction}
      unsupported = {Scheme::Unsupported, HashFunction::None}
      case identifier
      when ObjectIdentifiers::SHA256_WITH_RSA_ENCRYPTION, ObjectIdentifiers::SHA384_WITH_RSA_ENCRYPTION, ObjectIdentifiers::SHA512_WITH_RSA_ENCRYPTION
        # RFC 4055 §5: the parameters MUST be NULL; some issuers omit them,
        # which Go and OpenSSL accept, and so does Beryl.
        return unsupported unless parameters.nil? || (parameters.tag == Encoding::DER::NULL && parameters.content.empty?)
        hash = identifier == ObjectIdentifiers::SHA256_WITH_RSA_ENCRYPTION ? HashFunction::Sha256 : (identifier == ObjectIdentifiers::SHA384_WITH_RSA_ENCRYPTION ? HashFunction::Sha384 : HashFunction::Sha512)
        {Scheme::RsaPkcs1, hash}
      when ObjectIdentifiers::ECDSA_WITH_SHA256, ObjectIdentifiers::ECDSA_WITH_SHA384, ObjectIdentifiers::ECDSA_WITH_SHA512
        return unsupported unless parameters.nil? # RFC 5758 §3.2
        hash = identifier == ObjectIdentifiers::ECDSA_WITH_SHA256 ? HashFunction::Sha256 : (identifier == ObjectIdentifiers::ECDSA_WITH_SHA384 ? HashFunction::Sha384 : HashFunction::Sha512)
        {Scheme::Ecdsa, hash}
      when ObjectIdentifiers::ED25519
        return unsupported unless parameters.nil? # RFC 8410 §3
        {Scheme::Ed25519, HashFunction::None}
      when ObjectIdentifiers::RSASSA_PSS
        return unsupported unless parameters
        hash = pss_hash(parameters, reader)
        hash ? {Scheme::RsaPss, hash} : unsupported
      else
        unsupported
      end
    end

    # Reads RSASSA-PSS-params (RFC 4055 §3.1) and returns the hash when the
    # parameters are the ones Beryl accepts: the same SHA-2 hash for the
    # message and for MGF1, a salt as long as the hash, trailer field 1.
    private def self.pss_hash(parameters : Encoding::DER::Element, reader : Encoding::DER::Reader) : HashFunction?
      return nil unless parameters.tag == Encoding::DER::SEQUENCE

      reader.enter(parameters) do |sequence|
        hash_element = sequence.read_optional_element(Encoding::DER::Tag.context_specific(0, is_constructed: true))
        mask_element = sequence.read_optional_element(Encoding::DER::Tag.context_specific(1, is_constructed: true))
        salt_element = sequence.read_optional_element(Encoding::DER::Tag.context_specific(2, is_constructed: true))
        trailer_element = sequence.read_optional_element(Encoding::DER::Tag.context_specific(3, is_constructed: true))
        # The defaults are SHA-1, which Beryl refuses for signatures.
        return nil unless hash_element && mask_element && salt_element

        hash = sequence.enter(hash_element) { |inner| read_hash_identifier(inner) }
        mask_hash = sequence.enter(mask_element) do |inner|
          inner.read_sequence do |mask|
            return nil unless mask.read_object_identifier == ObjectIdentifiers::MGF1
            read_hash_identifier(mask)
          end
        end
        salt_bytesize = sequence.enter(salt_element) { |inner| inner.read_small_integer }
        if trailer_element
          trailer = sequence.enter(trailer_element) { |inner| inner.read_small_integer }
          return nil unless trailer == 1
        end
        return nil unless hash && hash == mask_hash && salt_bytesize == hash_bytesize(hash)

        hash
      end
    end

    private def self.read_hash_identifier(reader : Encoding::DER::Reader) : HashFunction?
      reader.read_sequence do |identifier|
        oid = identifier.read_object_identifier
        identifier.read_null unless identifier.at_end?
        case oid
        when ObjectIdentifiers::SHA256 then HashFunction::Sha256
        when ObjectIdentifiers::SHA384 then HashFunction::Sha384
        when ObjectIdentifiers::SHA512 then HashFunction::Sha512
        else                                nil
        end
      end
    end

    # :nodoc:
    def self.hash_bytesize(hash : HashFunction) : Int32
      case hash
      in .sha256? then 32
      in .sha384? then 48
      in .sha512? then 64
      in .none?   then 0
      end
    end

    def supported? : Bool
      !@scheme.unsupported?
    end

    # Returns whether *signature* is this algorithm's signature of *message*
    # under *key*. A key of the wrong type for the algorithm gives `false`.
    def verify(key : VerificationKey, message : Bytes, signature : Bytes) : Bool
      case @scheme
      in .rsa_pkcs1?
        return false unless key.is_a?(Crypto::V1::RSA::PublicKey)
        case @hash_function
        when .sha256? then key.verify_pkcs1_signature(message, signature, hash_function: Crypto::V1::SHA256)
        when .sha384? then key.verify_pkcs1_signature(message, signature, hash_function: Crypto::V1::SHA384)
        when .sha512? then key.verify_pkcs1_signature(message, signature, hash_function: Crypto::V1::SHA512)
        else               false
        end
      in .rsa_pss?
        return false unless key.is_a?(Crypto::V1::RSA::PublicKey)
        salt_bytesize = SignatureAlgorithm.hash_bytesize(@hash_function)
        case @hash_function
        when .sha256? then key.verify_pss_signature(message, signature, hash_function: Crypto::V1::SHA256, salt_bytesize: salt_bytesize)
        when .sha384? then key.verify_pss_signature(message, signature, hash_function: Crypto::V1::SHA384, salt_bytesize: salt_bytesize)
        when .sha512? then key.verify_pss_signature(message, signature, hash_function: Crypto::V1::SHA512, salt_bytesize: salt_bytesize)
        else               false
        end
      in .ecdsa?
        digest = case @hash_function
                 when .sha256? then Crypto::V1::SHA256.digest(message)
                 when .sha384? then Crypto::V1::SHA384.digest(message)
                 else               Crypto::V1::SHA512.digest(message)
                 end
        if key.is_a?(Crypto::V1::P256::PublicKey)
          key.verify_digest(digest, signature)
        elsif key.is_a?(Crypto::V1::P384::PublicKey)
          key.verify_digest(digest, signature)
        else
          false
        end
      in .ed25519?
        return false unless key.is_a?(Crypto::V1::Ed25519::VerificationKey)
        key.verify(message, signature)
      in .unsupported?
        false
      end
    end
  end
end
