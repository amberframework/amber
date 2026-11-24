module Amber::Beryl::TLS
  # The handshake transcript (RFC 9846 §4.4.1): every handshake message,
  # header included, in the order sent and received.
  #
  # The messages are kept as bytes until the handshake ends, so that the
  # hash can be chosen after the ServerHello names the suite, and so that
  # the first ClientHello can be replaced by its `message_hash` when a
  # HelloRetryRequest arrives. A handshake transcript is a few kilobytes
  # (each message is capped at 64 KiB by the record layer), and the hash is
  # taken about eight times per handshake.
  class TranscriptHash
    getter bytesize : Int32 = 0

    def initialize
      @messages = IO::Memory.new
    end

    # Appends one whole handshake message.
    def add(message : Bytes) : Nil
      @messages.write(message)
      @bytesize += message.size
    end

    # Returns the transcript hash of every message added.
    def digest(hash_algorithm : HashAlgorithm) : Bytes
      hash_algorithm.digest(@messages.to_slice)
    end

    # Returns the transcript hash as if *extra* had been added, without
    # adding it (the PSK binder hashes a ClientHello cut before its
    # binders, RFC 9846 §4.2.11.2).
    def digest_with(extra : Bytes, hash_algorithm : HashAlgorithm) : Bytes
      combined = Bytes.new(@bytesize + extra.size)
      @messages.to_slice.copy_to(combined)
      extra.copy_to(combined + @bytesize)
      hash_algorithm.digest(combined)
    end

    # Replaces the transcript, which must hold exactly the first
    # ClientHello, by the synthetic `message_hash` message that stands for
    # it after a HelloRetryRequest (RFC 9846 §4.4.1).
    def replace_with_message_hash(hash_algorithm : HashAlgorithm) : Nil
      first_client_hello_digest = digest(hash_algorithm)
      @messages = IO::Memory.new
      @bytesize = 0
      header = Bytes[HandshakeType::MessageHash.value, 0, 0, first_client_hello_digest.size.to_u8]
      add(header)
      add(first_client_hello_digest)
    end

    # Drops the stored messages once the handshake no longer needs them.
    def clear : Nil
      @messages = IO::Memory.new
      @bytesize = 0
    end
  end
end
