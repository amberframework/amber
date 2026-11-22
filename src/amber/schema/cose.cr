require "base64"
require "random/secure"
require "../vendor/beryl/crypto"

module Amber::Schema::COSE
  extend self

  CONTENT_TYPE          = "application/cose"
  TAG_ENCRYPT0          = 16_i64
  ALG_CHACHA20_POLY1305 = 24_i64
  HEADER_ALGORITHM      =  1_i64
  HEADER_KEY_ID         =  4_i64
  HEADER_IV             =  5_i64
  KEY_SIZE              =     32
  NONCE_SIZE            =     12
  TAG_SIZE              =     16

  class Error < RequestParseError
    def initialize(message = "Encrypted request authentication failed", code = "invalid_cose")
      super(message, code)
    end
  end

  # A process-wide provider contains immutable key material and supports an old
  # key grace window during rotation. A fresh nonce and cipher context are still
  # created for every message.
  class KeyProvider
    getter key_id : String

    @keys = {} of String => Bytes
    @rotation_lock = Mutex.new

    def initialize(key : Bytes, @key_id : String)
      add(@key_id, key)
    end

    def current_key : Bytes
      @keys[@key_id]
    end

    def add(key_id : String, key : Bytes) : self
      raise ArgumentError.new("COSE key must be #{KEY_SIZE} bytes") unless key.size == KEY_SIZE
      raise ArgumentError.new("COSE key id cannot be empty") if key_id.empty?
      # Publish a new immutable snapshot so active requests never observe a
      # Hash being mutated during key rotation. Reads stay lock-free.
      @rotation_lock.synchronize do
        keys = @keys.dup
        keys[key_id] = key.dup
        @keys = keys
      end
      self
    end

    def resolve(key_id : Bytes) : Bytes?
      @keys[String.new(key_id)]?
    end

    # There is intentionally no development fallback key. Applications must
    # make encryption an explicit configuration decision.
    def self.from_env!(key_variable = "AMBER_WIRE_KEY", key_id_variable = "AMBER_WIRE_KEY_ID") : self
      encoded = ENV[key_variable]? || raise ArgumentError.new("#{key_variable} is required for COSE")
      key_id = ENV[key_id_variable]? || raise ArgumentError.new("#{key_id_variable} is required for COSE")
      new(Base64.decode(encoded), key_id)
    end
  end

  module Configuration
    class_property key_provider : KeyProvider? = nil
  end

  def configure(provider : KeyProvider) : Nil
    Configuration.key_provider = provider
  end

  def key_provider : KeyProvider?
    Configuration.key_provider
  end

  def encrypt0(plaintext : Bytes, provider : KeyProvider, external_aad = Bytes.empty) : Bytes
    nonce = Random::Secure.random_bytes(NONCE_SIZE)
    protected_bytes = protected_header
    ciphertext = ChaCha20Poly1305.seal(
      provider.current_key,
      nonce,
      plaintext,
      encryption_structure(protected_bytes, external_aad)
    )

    io = IO::Memory.new
    CBOR.write_head(io, 6_u8, TAG_ENCRYPT0.to_u64)
    CBOR.write_head(io, 4_u8, 3_u64)
    CBOR.write_bytes(io, protected_bytes)
    CBOR.write_head(io, 5_u8, 2_u64)
    CBOR.write_int(io, HEADER_KEY_ID)
    CBOR.write_bytes(io, provider.key_id.to_slice)
    CBOR.write_int(io, HEADER_IV)
    CBOR.write_bytes(io, nonce)
    CBOR.write_bytes(io, ciphertext)
    io.to_slice.dup
  end

  # Decrypts a COSE_Encrypt0 message from *io*. With
  # *max_document_body_bytes*, a longer message raises
  # `Amber::Exceptions::ParameterLimitExceeded` before any declared length
  # is allocated.
  def decrypt0(io : IO, provider : KeyProvider, external_aad = Bytes.empty, max_document_body_bytes : Int32? = nil) : Bytes
    reader = CBOR::Reader.new(io, document_limit: max_document_body_bytes)
    raise Error.new unless reader.read_tag == TAG_ENCRYPT0
    raise Error.new unless reader.read_array_size == 3

    protected_bytes = reader.read_bytes
    validate_protected_header(protected_bytes)

    key_id = nil.as(Bytes?)
    nonce = nil.as(Bytes?)
    seen_key_id = false
    seen_nonce = false
    reader.read_map_size.times do
      case reader.read_int
      when HEADER_KEY_ID
        raise Error.new if seen_key_id
        seen_key_id = true
        key_id = reader.read_bytes
      when HEADER_IV
        raise Error.new if seen_nonce
        seen_nonce = true
        nonce = reader.read_bytes
      else
        raise Error.new
      end
    end

    ciphertext = reader.read_bytes
    reader.finish!
    resolved_key_id = key_id || raise Error.new
    resolved_nonce = nonce || raise Error.new
    raise Error.new unless resolved_nonce.size == NONCE_SIZE
    key = provider.resolve(resolved_key_id) || raise Error.new

    ChaCha20Poly1305.open(
      key,
      resolved_nonce,
      ciphertext,
      encryption_structure(protected_bytes, external_aad)
    ) || raise Error.new
  rescue ex : Error | Amber::Exceptions::ParameterLimitExceeded
    raise ex
  rescue
    raise Error.new
  end

  private def protected_header : Bytes
    io = IO::Memory.new
    CBOR.write_head(io, 5_u8, 1_u64)
    CBOR.write_int(io, HEADER_ALGORITHM)
    CBOR.write_int(io, ALG_CHACHA20_POLY1305)
    io.to_slice.dup
  end

  private def validate_protected_header(bytes : Bytes) : Nil
    reader = CBOR::Reader.new(IO::Memory.new(bytes), 256)
    raise Error.new unless reader.read_map_size == 1
    raise Error.new unless reader.read_int == HEADER_ALGORITHM
    raise Error.new unless reader.read_int == ALG_CHACHA20_POLY1305
    reader.finish!
  rescue
    raise Error.new
  end

  private def encryption_structure(protected_bytes : Bytes, external_aad : Bytes) : Bytes
    io = IO::Memory.new
    CBOR.write_head(io, 4_u8, 3_u64)
    CBOR.write_text(io, "Encrypt0")
    CBOR.write_bytes(io, protected_bytes)
    CBOR.write_bytes(io, external_aad)
    io.to_slice.dup
  end

  # ChaCha20-Poly1305 (RFC 8439), COSE algorithm 24, from Beryl's
  # implementation in Crystal. The COSE profile is portable at the wire
  # level; clients can use CryptoKit, WebCrypto-compatible adapters, or any
  # RFC 8439 implementation.
  module ChaCha20Poly1305
    extend self

    # Returns the ciphertext of *plaintext* followed by its 16-byte tag.
    def seal(key : Bytes, nonce : Bytes, plaintext : Bytes, aad = Bytes.empty) : Bytes
      validate_sizes(key, nonce)
      Amber::Beryl::Crypto::V1::ChaCha20Poly1305.new(key).encrypt(plaintext, nonce: nonce, associated_data: aad)
    end

    # Returns the plaintext of *ciphertext_and_tag*, or nil when the tag does
    # not match. Nothing is decrypted before the tag has been checked.
    def open(key : Bytes, nonce : Bytes, ciphertext_and_tag : Bytes, aad = Bytes.empty) : Bytes?
      validate_sizes(key, nonce)
      return nil if ciphertext_and_tag.size < TAG_SIZE

      Amber::Beryl::Crypto::V1::ChaCha20Poly1305.new(key).decrypt(ciphertext_and_tag, nonce: nonce, associated_data: aad)
    end

    private def validate_sizes(key : Bytes, nonce : Bytes) : Nil
      raise ArgumentError.new("COSE key must be #{KEY_SIZE} bytes") unless key.size == KEY_SIZE
      raise ArgumentError.new("COSE nonce must be #{NONCE_SIZE} bytes") unless nonce.size == NONCE_SIZE
    end
  end
end
