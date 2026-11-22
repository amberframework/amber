require "crypto/subtle"
require "digest/digest"
require "../error"
require "../secret_wiping"
require "./block_hash_function"

module Amber::Beryl::Crypto::V1
  # HMAC (RFC 2104, FIPS 198-1): a message authentication code built on the
  # hash function `D`. Someone who holds the key can produce the tag for a
  # message; nobody else can produce or alter one.
  #
  # `D` is any hash of this shard, for example `HMAC(SHA256)`. The instance
  # streams like a `::Digest`: `update` any number of times, then `final` for
  # the tag or `verify` to check a tag received from outside.
  #
  # ```
  # tag = Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::V1::SHA256).authenticate("message", key: "secret key")
  #
  # authentication = Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::V1::SHA256).new("secret key")
  # authentication.update("mess").update("age")
  # authentication.verify(tag) # => true
  # ```
  #
  # The key is never kept: construction turns it into two keyed hash states
  # and wipes the working copies. Checking a tag takes the same time whatever
  # the key, the message or the candidate tag hold.
  class HashBasedMessageAuthenticationCode(D) < ::Digest
    # The shortest truncated tag `verify` accepts, in bytes: 80 bits
    # (RFC 2104 §5).
    MINIMUM_TRUNCATED_TAG_BYTESIZE = 10

    private INNER_PADDING_BYTE = 0x36_u8
    private OUTER_PADDING_BYTE = 0x5c_u8

    @inner_hash : D
    @outer_hash : D
    @inner_hash_after_key : D
    @outer_hash_after_key : D

    # Returns the authentication tag of *message* under *key* in one call.
    def self.authenticate(message : Bytes | String, *, key : Bytes | String) : Bytes
      new(key).update(message).final
    end

    # Returns whether *authentication_tag* is the tag of *message* under
    # *key*, comparing in constant time.
    def self.verify(message : Bytes | String, authentication_tag : Bytes, *, key : Bytes | String) : Bool
      new(key).update(message).verify(authentication_tag)
    end

    # Creates an authentication under *key*. A key longer than the hash's
    # block is hashed first, as RFC 2104 §2 requires; the key's length is the
    # only thing about it that decides any step.
    def initialize(key : Bytes | String)
      @inner_hash = D.new
      @outer_hash = D.new
      @inner_hash_after_key = D.new
      @outer_hash_after_key = D.new

      key_block_storage = StaticArray(UInt8, BlockHashFunction::LARGEST_BLOCK_SIZE).new(0_u8)
      padded_block_storage = uninitialized UInt8[BlockHashFunction::LARGEST_BLOCK_SIZE]
      # Sizes come from the instance, which also works when an application
      # subclasses the hash (a constant read through the type argument does not).
      block_bytesize = @inner_hash.block_size
      key_block = key_block_storage.to_slice[0, block_bytesize]
      padded_block = padded_block_storage.to_slice[0, block_bytesize]

      key_bytes = key.to_slice
      if key_bytes.size > block_bytesize
        D.new.update(key_bytes).final(key_block[0, digest_size])
      else
        key_bytes.copy_to(key_block)
      end

      block_bytesize.times { |index| padded_block[index] = key_block[index] ^ INNER_PADDING_BYTE }
      @inner_hash_after_key.update(padded_block)
      block_bytesize.times { |index| padded_block[index] = key_block[index] ^ OUTER_PADDING_BYTE }
      @outer_hash_after_key.update(padded_block)

      SecretWiping.wipe(key_block_storage.to_slice)
      SecretWiping.wipe(padded_block_storage.to_slice)

      reset_impl
    end

    # Builds a copy from another authentication's four hash states.
    protected def initialize(@inner_hash : D, @outer_hash : D, @inner_hash_after_key : D, @outer_hash_after_key : D,
                             @finished : Bool)
    end

    # Returns an independent authentication under the same key that continues
    # from the point this one has reached.
    def dup : self
      self.class.new(@inner_hash.dup, @outer_hash.dup, @inner_hash_after_key.dup, @outer_hash_after_key.dup, @finished)
    end

    # Returns the number of bytes in a full authentication tag.
    def digest_size : Int32
      @inner_hash.digest_size
    end

    # Finishes the authentication and returns whether *authentication_tag* is
    # the tag of everything passed to `update`.
    #
    # The comparison runs in constant time, and a tag of the wrong length is
    # refused only after the same hashing and the same comparison as a tag of
    # the right length.
    #
    # *truncated_to_bytesize* checks a tag that the protocol cuts to its
    # leading bytes (RFC 2104 §5). It must be at least half the full tag and
    # at least `MINIMUM_TRUNCATED_TAG_BYTESIZE`; anything shorter raises
    # `TruncatedTagTooShort`.
    def verify(authentication_tag : Bytes, *, truncated_to_bytesize : Int32 = digest_size) : Bool
      shortest_accepted_bytesize = Math.max(digest_size // 2, MINIMUM_TRUNCATED_TAG_BYTESIZE)
      unless shortest_accepted_bytesize <= truncated_to_bytesize <= digest_size
        raise TruncatedTagTooShort.new(
          "a tag from this hash is checked at #{shortest_accepted_bytesize} to #{digest_size} bytes, not #{truncated_to_bytesize}"
        )
      end

      full_tag_storage = uninitialized UInt8[BlockHashFunction::LARGEST_DIGEST_SIZE]
      full_tag = full_tag_storage.to_slice[0, digest_size]
      final(full_tag)
      expected_tag = full_tag[0, truncated_to_bytesize]

      # A candidate of the wrong length is replaced by the expected tag so the
      # comparison below still walks every byte; the length check then decides.
      has_the_expected_bytesize = authentication_tag.size == expected_tag.size
      comparable_tag = has_the_expected_bytesize ? authentication_tag : expected_tag
      tags_match = ::Crypto::Subtle.constant_time_compare(expected_tag, comparable_tag)

      SecretWiping.wipe(full_tag_storage.to_slice)
      tags_match & has_the_expected_bytesize
    end

    private def update_impl(data : Bytes) : Nil
      @inner_hash.update(data)
    end

    private def final_impl(dst : Bytes) : Nil
      unless dst.size == digest_size
        raise OutputSizeMismatch.new("the authentication tag is #{digest_size} bytes, the buffer holds #{dst.size}")
      end

      inner_digest_storage = uninitialized UInt8[BlockHashFunction::LARGEST_DIGEST_SIZE]
      inner_digest = inner_digest_storage.to_slice[0, digest_size]
      @inner_hash.final(inner_digest)
      @outer_hash.update(inner_digest)
      @outer_hash.final(dst)
      SecretWiping.wipe(inner_digest_storage.to_slice)
    end

    private def reset_impl : Nil
      @inner_hash.copy_state_from(@inner_hash_after_key)
      @outer_hash.copy_state_from(@outer_hash_after_key)
    end
  end

  # The common name of `HashBasedMessageAuthenticationCode`.
  alias HMAC = HashBasedMessageAuthenticationCode
end
