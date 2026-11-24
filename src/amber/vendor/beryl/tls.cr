require "./crypto"
require "./certificates"
require "./tls/protocol"
require "./tls/error"
require "./tls/hash_algorithm"
require "./tls/transcript_hash"
require "./tls/key_schedule"
require "./tls/limits"
require "./tls/record_protection"
require "./tls/record_layer"
require "./tls/messages/message_reader"
require "./tls/messages/handshake_messages"
require "./tls/messages/extension_codec"
require "./tls/handshake_randomness"
require "./tls/certified_key"
require "./tls/certificate_verifier"
require "./tls/session_ticket"
require "./tls/context"
require "./tls/handshake_outcome"
require "./tls/client_handshake"
require "./tls/server_handshake"
require "./tls/socket"

# TLS 1.3 (RFC 9846) written in Crystal, on Beryl's own cryptography.
#
# Beryl offers `TLS_AES_128_GCM_SHA256`, `TLS_CHACHA20_POLY1305_SHA256` and
# `TLS_AES_256_GCM_SHA384`, key exchange on `x25519` and `secp256r1`, and
# never 0-RTT, renegotiation or compression (plan §2).
module Amber::Beryl::TLS
end
