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
  end
end
