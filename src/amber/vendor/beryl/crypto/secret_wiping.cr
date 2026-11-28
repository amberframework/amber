module Amber::Beryl::Crypto
  # :nodoc:
  #
  # Overwrites buffers that held secret material.
  module SecretWiping
    # Fills *secret_bytes* with zeros through a volatile write, which the
    # optimizer must keep even when the buffer is never read again.
    def self.wipe(secret_bytes : Bytes) : Nil
      return if secret_bytes.empty?

      Intrinsics.memset(secret_bytes.to_unsafe.as(Void*), 0_u8, secret_bytes.size, true)
    end

    # Fills *secret_words* (round keys, hash key state) with zeros, as
    # `wipe(Bytes)` does.
    def self.wipe(secret_words : Slice(UInt64)) : Nil
      wipe(Bytes.new(secret_words.to_unsafe.as(UInt8*), secret_words.bytesize))
    end
  end
end
