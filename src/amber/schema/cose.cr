require "base64"
require "openssl"
require "random/secure"

lib LibCrypto
  fun evp_cipher_ctx_ctrl = EVP_CIPHER_CTX_ctrl(ctx : EVP_CIPHER_CTX, type : Int32, arg : Int32, ptr : Void*) : Int32
end

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

  def decrypt0(io : IO, provider : KeyProvider, external_aad = Bytes.empty) : Bytes
    reader = CBOR::Reader.new(io)
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
  rescue ex : Error
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

  # OpenSSL's maintained ChaCha20-Poly1305 implementation. The COSE profile is
  # portable at the wire level; clients can use CryptoKit, WebCrypto-compatible
  # adapters, or any RFC 8439 implementation.
  module ChaCha20Poly1305
    extend self

    EVP_CTRL_AEAD_SET_IVLEN =  0x9
    EVP_CTRL_AEAD_GET_TAG   = 0x10
    EVP_CTRL_AEAD_SET_TAG   = 0x11

    def seal(key : Bytes, nonce : Bytes, plaintext : Bytes, aad = Bytes.empty) : Bytes
      validate_sizes(key, nonce)
      context = LibCrypto.evp_cipher_ctx_new
      raise Error.new("Unable to initialize COSE encryption", "cose_crypto_error") if context.null?

      begin
        cipher = LibCrypto.evp_get_cipherbyname("chacha20-poly1305")
        raise Error.new("ChaCha20-Poly1305 is unavailable", "cose_algorithm_unavailable") if cipher.null?
        check LibCrypto.evp_cipherinit_ex(context, cipher, Pointer(Void).null, Pointer(UInt8).null, Pointer(UInt8).null, 1)
        check LibCrypto.evp_cipher_ctx_ctrl(context, EVP_CTRL_AEAD_SET_IVLEN, nonce.size, Pointer(Void).null)
        check LibCrypto.evp_cipherinit_ex(context, Pointer(Void).null, Pointer(Void).null, key, nonce, 1)
        update_aad(context, aad)
        ciphertext = update(context, plaintext)
        final = finalize(context).not_nil!
        tag = Bytes.new(TAG_SIZE)
        check LibCrypto.evp_cipher_ctx_ctrl(context, EVP_CTRL_AEAD_GET_TAG, TAG_SIZE, tag.to_unsafe.as(Void*))
        concatenate(ciphertext, final, tag)
      ensure
        LibCrypto.evp_cipher_ctx_free(context)
      end
    end

    def open(key : Bytes, nonce : Bytes, ciphertext_and_tag : Bytes, aad = Bytes.empty) : Bytes?
      validate_sizes(key, nonce)
      return nil if ciphertext_and_tag.size < TAG_SIZE
      ciphertext = ciphertext_and_tag[0, ciphertext_and_tag.size - TAG_SIZE]
      tag = ciphertext_and_tag[ciphertext_and_tag.size - TAG_SIZE, TAG_SIZE]
      context = LibCrypto.evp_cipher_ctx_new
      return nil if context.null?

      begin
        cipher = LibCrypto.evp_get_cipherbyname("chacha20-poly1305")
        return nil if cipher.null?
        return nil unless ok? LibCrypto.evp_cipherinit_ex(context, cipher, Pointer(Void).null, Pointer(UInt8).null, Pointer(UInt8).null, 0)
        return nil unless ok? LibCrypto.evp_cipher_ctx_ctrl(context, EVP_CTRL_AEAD_SET_IVLEN, nonce.size, Pointer(Void).null)
        return nil unless ok? LibCrypto.evp_cipherinit_ex(context, Pointer(Void).null, Pointer(Void).null, key, nonce, 0)
        update_aad(context, aad)
        plaintext = update(context, ciphertext)
        return nil unless ok? LibCrypto.evp_cipher_ctx_ctrl(context, EVP_CTRL_AEAD_SET_TAG, TAG_SIZE, tag.to_unsafe.as(Void*))
        tail = finalize(context, raise_on_error: false)
        return nil unless tail
        concatenate(plaintext, tail, Bytes.empty)
      rescue
        nil
      ensure
        LibCrypto.evp_cipher_ctx_free(context)
      end
    end

    private def validate_sizes(key : Bytes, nonce : Bytes) : Nil
      raise ArgumentError.new("COSE key must be #{KEY_SIZE} bytes") unless key.size == KEY_SIZE
      raise ArgumentError.new("COSE nonce must be #{NONCE_SIZE} bytes") unless nonce.size == NONCE_SIZE
    end

    private def update_aad(context, aad : Bytes) : Nil
      return if aad.empty?
      length = 0
      check LibCrypto.evp_cipherupdate(context, Pointer(UInt8).null, pointerof(length), aad, aad.size)
    end

    private def update(context, input : Bytes) : Bytes
      return Bytes.empty if input.empty?
      output = Bytes.new(input.size + 16)
      length = 0
      check LibCrypto.evp_cipherupdate(context, output, pointerof(length), input, input.size)
      output[0, length].dup
    end

    private def finalize(context, raise_on_error = true) : Bytes?
      output = Bytes.new(16)
      length = 0
      result = LibCrypto.evp_cipherfinal_ex(context, output, pointerof(length))
      if result != 1
        raise Error.new if raise_on_error
        return nil
      end
      output[0, length].dup
    end

    private def concatenate(first : Bytes, second : Bytes, third : Bytes) : Bytes
      output = Bytes.new(first.size + second.size + third.size)
      first.copy_to(output)
      second.copy_to(output + first.size)
      third.copy_to(output + first.size + second.size)
      output
    end

    private def check(result : Int32) : Nil
      raise Error.new("COSE cryptographic operation failed", "cose_crypto_error") unless ok?(result)
    end

    private def ok?(result : Int32) : Bool
      result == 1
    end
  end
end
