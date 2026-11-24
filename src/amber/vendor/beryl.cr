require "log"
require "./beryl/version"
require "./beryl/error"
require "./beryl/crypto"
require "./beryl/encoding"
require "./beryl/certificates"

# Security for Amber V2.
#
# `Amber::Beryl::Crypto` holds the cryptography: hashes, message authentication and
# key derivation written in Crystal, with no C library underneath.
module Amber::Beryl
  # The log source for the whole shard (`beryl`). Beryl logs with the block
  # form and never logs a key, a message or an authentication tag.
  Log = ::Log.for(self)
end
