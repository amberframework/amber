require "../crypto/secret_wiping"
require "./key_schedule"

module Amber::Beryl::TLS
  # One direction of record protection (RFC 9846 §5.2 and §5.3): the AEAD
  # keyed from a traffic secret, its IV, and the sequence number.
  #
  # ```
  # protection = Amber::Beryl::TLS::RecordProtection.new(CipherSuite::TLS_AES_128_GCM_SHA256, traffic_secret)
  # record = protection.seal(ContentType::ApplicationData, "hello".to_slice)
  # protection_of_peer.open(record[0, 5], record[5..]) # => {ContentType::ApplicationData, Bytes}
  # ```
  class RecordProtection
    # The record header: type, legacy version, length.
    HEADER_BYTESIZE = 5
    # The largest TLSInnerPlaintext: 2^14 bytes of content and its type.
    LARGEST_INNER_PLAINTEXT_BYTESIZE = 16_385
    # The largest TLSCiphertext fragment (§5.2).
    LARGEST_CIPHERTEXT_BYTESIZE = 16_640

    getter cipher_suite : CipherSuite
    getter sequence_number : UInt64 = 0_u64

    @authenticated_encryption : Crypto::V1::AuthenticatedEncryption
    @iv : Bytes
    @nonce : Bytes

    def initialize(@cipher_suite : CipherSuite, traffic_secret : Bytes)
      key, @iv = KeySchedule.traffic_key_and_iv(@cipher_suite.hash_algorithm, traffic_secret, @cipher_suite.key_bytesize)
      @authenticated_encryption = @cipher_suite.build_authenticated_encryption(key)
      Crypto::SecretWiping.wipe(key)
      @nonce = Bytes.new(KeySchedule::IV_BYTESIZE)
    end

    # The tag size of every TLS 1.3 AEAD.
    def tag_bytesize : Int32
      16
    end

    # Returns a whole protected record (header and ciphertext) carrying
    # *content* of *content_type*, with *padding_bytesize* zero bytes of
    # padding (§5.4).
    def seal(content_type : ContentType, content : Bytes, padding_bytesize : Int32 = 0) : Bytes
      inner_bytesize = content.size + 1 + padding_bytesize
      seal(content_type, content, padding_bytesize,
        into: Bytes.new(HEADER_BYTESIZE + inner_bytesize + tag_bytesize), scratch: Bytes.new(inner_bytesize))
    end

    # :nodoc:
    #
    # Seals as `seal` does, into the front of *record_storage*, building the
    # inner plaintext in *scratch* (wiped afterward). Returns the record, a
    # slice of *record_storage*. `RecordLayer` passes buffers it reuses, so
    # a connection does not allocate for each record it writes.
    def seal(content_type : ContentType, content : Bytes, padding_bytesize : Int32 = 0, *,
             into record_storage : Bytes, scratch : Bytes) : Bytes
      inner_bytesize = content.size + 1 + padding_bytesize
      if inner_bytesize > LARGEST_INNER_PLAINTEXT_BYTESIZE
        raise Error.new("a record of #{inner_bytesize} bytes of inner plaintext", AlertDescription::InternalError)
      end
      ciphertext_bytesize = inner_bytesize + tag_bytesize
      record = record_storage[0, HEADER_BYTESIZE + ciphertext_bytesize]
      record[0] = ContentType::ApplicationData.value
      record[1] = 0x03
      record[2] = 0x03
      record[3] = (ciphertext_bytesize >> 8).to_u8
      record[4] = (ciphertext_bytesize & 0xFF).to_u8

      inner_plaintext = scratch[0, inner_bytesize]
      content.copy_to(inner_plaintext)
      inner_plaintext[content.size] = content_type.value
      inner_plaintext[content.size + 1, padding_bytesize].fill(0_u8)
      @authenticated_encryption.encrypt(inner_plaintext, into: record + HEADER_BYTESIZE, nonce: next_nonce,
        associated_data: record[0, HEADER_BYTESIZE])
      Crypto::SecretWiping.wipe(inner_plaintext)
      record
    end

    # Opens the record with *header* and *ciphertext*. Returns the inner
    # content type and content, or `nil` when the record fails
    # authentication; raises for a record with no content type.
    def open(header : Bytes, ciphertext : Bytes) : {ContentType, Bytes}?
      return nil if ciphertext.size < tag_bytesize
      open(header, ciphertext, into: Bytes.new(ciphertext.size - tag_bytesize))
    end

    # :nodoc:
    #
    # Opens as `open` does, decrypting into the front of *plaintext_storage*;
    # the content returned is a slice of it. `RecordLayer` passes a buffer it
    # reuses.
    def open(header : Bytes, ciphertext : Bytes, *, into plaintext_storage : Bytes) : {ContentType, Bytes}?
      return nil if ciphertext.size < tag_bytesize
      inner_plaintext = plaintext_storage[0, ciphertext.size - tag_bytesize]
      nonce = peek_nonce
      return nil unless @authenticated_encryption.decrypt(ciphertext, into: inner_plaintext, nonce: nonce, associated_data: header)
      advance_sequence_number
      # Content, type and padding together stay within 2^14 + 1 bytes (§5.4).
      if inner_plaintext.size > LARGEST_INNER_PLAINTEXT_BYTESIZE
        raise Error.new("a protected record with #{inner_plaintext.size} bytes of inner plaintext", AlertDescription::RecordOverflow)
      end

      # The padding is zeros after the content type; its length is chosen
      # by the sender and is not secret from the receiver (§5.4).
      type_index = inner_plaintext.size - 1
      while type_index >= 0 && inner_plaintext[type_index] == 0
        type_index -= 1
      end
      if type_index < 0
        raise Error.new("a protected record with no content type", AlertDescription::UnexpectedMessage)
      end
      {ContentType.new(inner_plaintext[type_index]), inner_plaintext[0, type_index]}
    end

    # Wipes the key material this direction holds.
    def wipe : Nil
      Crypto::SecretWiping.wipe(@iv)
      Crypto::SecretWiping.wipe(@nonce)
    end

    private def next_nonce : Bytes
      nonce = peek_nonce
      advance_sequence_number
      nonce
    end

    # The per-record nonce: the IV with the sequence number, as 64
    # big-endian bits, xored into its last 8 bytes (§5.3).
    private def peek_nonce : Bytes
      @iv.copy_to(@nonce)
      8.times do |index|
        @nonce[KeySchedule::IV_BYTESIZE - 1 - index] ^= ((@sequence_number >> (8 * index)) & 0xFF).to_u8
      end
      @nonce
    end

    private def advance_sequence_number : Nil
      if @sequence_number == UInt64::MAX
        raise Error.new("the sequence number would wrap", AlertDescription::InternalError)
      end
      @sequence_number += 1
    end
  end
end
