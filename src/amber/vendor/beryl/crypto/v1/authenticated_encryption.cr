require "crypto/subtle"
require "../declassification"
require "../data_independent_timing"
require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # Encryption that also proves a message is whole and came from someone who
  # holds the key (authenticated encryption with associated data, RFC 5116).
  # `ChaCha20Poly1305`, `XChaCha20Poly1305` and `AESGCM` are the ciphers; this
  # class is what they share.
  #
  # ```
  # cipher = Amber::Beryl::Crypto::V1::XChaCha20Poly1305.new(key)
  # nonce = Random::Secure.random_bytes(cipher.nonce_bytesize)
  # sealed = cipher.encrypt("a private note", nonce: nonce, associated_data: "note 42")
  # cipher.decrypt(sealed, nonce: nonce, associated_data: "note 42") # => the note's bytes
  # cipher.decrypt(sealed, nonce: nonce, associated_data: "note 43") # => nil
  # ```
  #
  # An encrypted message is the ciphertext followed by the authentication
  # tag. *associated_data* is authenticated and left readable; both sides
  # must supply the same bytes. A nonce must never repeat under one key.
  #
  # Decryption checks the tag before it returns a single byte of plaintext:
  # a message that fails the check returns `nil` (or `false`), and the
  # caller's `into:` buffer is overwritten with zeros, whatever its length
  # and whichever code ran (a cipher may decrypt while it checks). The check
  # takes the same time whatever the key, the message and the tag hold.
  #
  # `wipe` zeroes every buffer derived from the key; after it, every
  # encryption, decryption and tag check raises `KeyWiped`.
  abstract class AuthenticatedEncryption
    # The size of a full tag, in bytes, for every cipher in this shard.
    FULL_TAG_BYTESIZE = 16

    # Returns the number of bytes of tag at the end of each encrypted message.
    getter tag_bytesize : Int32 = FULL_TAG_BYTESIZE

    # Returns whether `wipe` has zeroed this cipher's key.
    getter? is_wiped : Bool = false

    # Zeroes the key and everything derived from it (round keys, hash keys)
    # through `SecretWiping`. The cipher cannot be used afterward: every
    # encryption, decryption and tag check raises `KeyWiped`.
    def wipe : Nil
      @is_wiped = true
      wipe_key_material
    end

    # Zeroes, in place, every buffer this cipher derived from its key.
    protected abstract def wipe_key_material : Nil

    # Returns the nonce size this cipher is meant to be used with, in bytes.
    abstract def nonce_bytesize : Int32

    # Raises `NonceSizeMismatch` unless this cipher accepts *nonce*.
    protected abstract def ensure_nonce_is_accepted(nonce : Bytes) : Nil

    # XORs *input* into *output* with the keystream of *nonce*.
    protected abstract def apply_keystream(nonce : Bytes, input : Bytes, output : Bytes) : Nil

    # Writes into *full_tag* (`FULL_TAG_BYTESIZE` bytes) the tag of
    # *ciphertext* and *associated_data* under *nonce*.
    protected abstract def compute_tag(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil

    # Writes the plaintext of *ciphertext* into *plaintext* and returns true
    # when *tag* (the received tag, `tag_bytesize` bytes) is right; returns
    # false otherwise, and may have written into *plaintext* by then
    # (`decrypt` zeroes it). A cipher whose
    # keystream also gives its authentication key overrides this to make
    # both from one pass.
    protected def open(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      full_tag_storage = uninitialized UInt8[FULL_TAG_BYTESIZE]
      compute_tag(nonce, associated_data, ciphertext, full_tag_storage.to_slice)
      tags_match = ::Crypto::Subtle.constant_time_compare(full_tag_storage.to_slice[0, tag.size], tag)
      SecretWiping.wipe(full_tag_storage.to_slice)
      return false unless Declassification.reveal(tags_match)

      apply_keystream(nonce, ciphertext, plaintext)
      true
    end

    # Encrypts *plaintext* into *ciphertext* under *nonce* and writes into
    # *full_tag* the tag of the ciphertext and *associated_data*. A cipher
    # that can encrypt and authenticate in one pass over the message
    # overrides this.
    protected def seal(nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      apply_keystream(nonce, plaintext, ciphertext)
      compute_tag(nonce, associated_data, ciphertext, full_tag)
    end

    # Returns *plaintext* encrypted under *nonce*: the ciphertext, then the
    # tag.
    def encrypt(plaintext : Bytes | String, *, nonce : Bytes, associated_data : Bytes | String = Bytes.empty) : Bytes
      ciphertext_and_tag = Bytes.new(plaintext.to_slice.size + @tag_bytesize)
      encrypt(plaintext, into: ciphertext_and_tag, nonce: nonce, associated_data: associated_data)
      ciphertext_and_tag
    end

    # Encrypts *plaintext* under *nonce* into *ciphertext_and_tag*, which
    # must be `tag_bytesize` bytes longer than the plaintext.
    def encrypt(plaintext : Bytes | String, *, into ciphertext_and_tag : Bytes, nonce : Bytes,
                associated_data : Bytes | String = Bytes.empty) : Nil
      ensure_key_is_not_wiped
      plaintext_bytes = plaintext.to_slice
      ensure_nonce_is_accepted(nonce)
      unless ciphertext_and_tag.size == plaintext_bytes.size + @tag_bytesize
        raise OutputSizeMismatch.new(
          "the encrypted message is #{plaintext_bytes.size + @tag_bytesize} bytes, the buffer holds #{ciphertext_and_tag.size}"
        )
      end

      ciphertext = ciphertext_and_tag[0, plaintext_bytes.size]
      full_tag_storage = uninitialized UInt8[FULL_TAG_BYTESIZE]
      DataIndependentTiming.run do
        seal(nonce, associated_data.to_slice, plaintext_bytes, ciphertext, full_tag_storage.to_slice)
        full_tag_storage.to_slice[0, @tag_bytesize].copy_to(ciphertext_and_tag[plaintext_bytes.size, @tag_bytesize])
        SecretWiping.wipe(full_tag_storage.to_slice)
      end
    end

    # Returns the plaintext of *ciphertext_and_tag*, or `nil` when the
    # message, the nonce or the associated data is not what was encrypted.
    def decrypt(ciphertext_and_tag : Bytes, *, nonce : Bytes, associated_data : Bytes | String = Bytes.empty) : Bytes?
      ensure_key_is_not_wiped
      ensure_nonce_is_accepted(nonce)
      return nil if ciphertext_and_tag.size < @tag_bytesize

      plaintext = Bytes.new(ciphertext_and_tag.size - @tag_bytesize)
      return nil unless decrypt(ciphertext_and_tag, into: plaintext, nonce: nonce, associated_data: associated_data)

      plaintext
    end

    # Decrypts *ciphertext_and_tag* into *plaintext*, which must be
    # `tag_bytesize` bytes shorter, and returns true; or returns false and
    # overwrites all of *plaintext* with zeros when the message fails
    # authentication.
    def decrypt(ciphertext_and_tag : Bytes, *, into plaintext : Bytes, nonce : Bytes,
                associated_data : Bytes | String = Bytes.empty) : Bool
      ensure_key_is_not_wiped
      ensure_nonce_is_accepted(nonce)
      if ciphertext_and_tag.size < @tag_bytesize
        SecretWiping.wipe(plaintext)
        return false
      end
      unless plaintext.size == ciphertext_and_tag.size - @tag_bytesize
        raise OutputSizeMismatch.new(
          "the plaintext is #{ciphertext_and_tag.size - @tag_bytesize} bytes, the buffer holds #{plaintext.size}"
        )
      end

      # `open` reveals its verdict where it computes it; revealing it again
      # here tells the secret-flow check that the caller sees a public value.
      is_authentic = Declassification.reveal(DataIndependentTiming.run do
        open(nonce, associated_data.to_slice, ciphertext_and_tag[0, plaintext.size],
          ciphertext_and_tag[plaintext.size, @tag_bytesize], plaintext)
      end)
      # The same buffer on a failure from every cipher and every path: zeros.
      SecretWiping.wipe(plaintext) unless is_authentic
      is_authentic
    end

    # Returns whether *ciphertext_and_tag* carries the right tag for *nonce*
    # and *associated_data*, without decrypting it. The comparison runs in
    # constant time.
    def authentic?(ciphertext_and_tag : Bytes, *, nonce : Bytes, associated_data : Bytes | String = Bytes.empty) : Bool
      ensure_key_is_not_wiped
      ensure_nonce_is_accepted(nonce)
      return false if ciphertext_and_tag.size < @tag_bytesize

      ciphertext_bytesize = ciphertext_and_tag.size - @tag_bytesize
      full_tag_storage = uninitialized UInt8[FULL_TAG_BYTESIZE]
      tags_match = DataIndependentTiming.run do
        compute_tag(nonce, associated_data.to_slice, ciphertext_and_tag[0, ciphertext_bytesize], full_tag_storage.to_slice)
        ::Crypto::Subtle.constant_time_compare(
          full_tag_storage.to_slice[0, @tag_bytesize],
          ciphertext_and_tag[ciphertext_bytesize, @tag_bytesize]
        )
      end
      SecretWiping.wipe(full_tag_storage.to_slice)
      tags_match
    end

    # One check per call, before any secret is touched; `@is_wiped` is
    # public state, so the branch leaks nothing.
    private def ensure_key_is_not_wiped : Nil
      raise KeyWiped.new("this #{self.class.name} was wiped; its key can no longer seal or open a message") if @is_wiped
    end
  end

  # The common name of `AuthenticatedEncryption`.
  alias AEAD = AuthenticatedEncryption
end
