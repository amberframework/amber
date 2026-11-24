require "../crypto/secret_wiping"
require "./hash_algorithm"

module Amber::Beryl::TLS
  # The TLS 1.3 key schedule (RFC 9846 §7.1): the early, handshake and
  # master secrets, and every secret, key and Finished value derived from
  # them.
  #
  # ```
  # schedule = Amber::Beryl::TLS::KeySchedule.new(HashAlgorithm::SHA256)
  # schedule.enter_handshake_stage(ecdhe_shared_secret)
  # client_secret = schedule.client_handshake_traffic_secret(transcript_digest)
  # key, iv = Amber::Beryl::TLS::KeySchedule.traffic_key_and_iv(HashAlgorithm::SHA256, client_secret, 16)
  # ```
  #
  # Each stage's secret is wiped when the next one is entered; the secrets
  # handed out are the caller's to wipe.
  class KeySchedule
    # The size of an AEAD nonce for every TLS 1.3 suite (§5.3).
    IV_BYTESIZE = 12

    getter hash_algorithm : HashAlgorithm

    @early_secret : Bytes
    @handshake_secret : Bytes? = nil
    @master_secret : Bytes? = nil

    # Starts the schedule with the early secret, from *pre_shared_key* when
    # resuming and from a string of zeros otherwise.
    def initialize(@hash_algorithm : HashAlgorithm, pre_shared_key : Bytes? = nil)
      zeros = Bytes.new(@hash_algorithm.bytesize)
      @early_secret = @hash_algorithm.extract(pre_shared_key || zeros, salt: zeros)
    end

    # HKDF-Expand-Label (§7.1): *label* gets the `tls13 ` prefix.
    def self.expand_label(hash_algorithm : HashAlgorithm, secret : Bytes, label : String, context : Bytes, bytesize : Int32) : Bytes
      full_label_bytesize = 6 + label.bytesize
      raise ArgumentError.new("a label of #{label.bytesize} bytes") if full_label_bytesize > 255 || context.size > 255
      info = Bytes.new(2 + 1 + full_label_bytesize + 1 + context.size)
      info[0] = (bytesize >> 8).to_u8
      info[1] = (bytesize & 0xFF).to_u8
      info[2] = full_label_bytesize.to_u8
      "tls13 ".to_slice.copy_to(info + 3)
      label.to_slice.copy_to(info + 9)
      info[3 + full_label_bytesize] = context.size.to_u8
      context.copy_to(info + (4 + full_label_bytesize))
      hash_algorithm.expand(secret, info: info, bytesize: bytesize)
    end

    # Derive-Secret (§7.1), given the transcript hash already taken.
    def self.derive_secret(hash_algorithm : HashAlgorithm, secret : Bytes, label : String, transcript_digest : Bytes) : Bytes
      expand_label(hash_algorithm, secret, label, transcript_digest, hash_algorithm.bytesize)
    end

    # The early secret, for specs and for the binder of an external PSK.
    def early_secret : Bytes
      @early_secret
    end

    # The key the PSK binders are computed under (`res binder`, §7.1).
    def resumption_binder_key : Bytes
      derive(@early_secret, "res binder", @hash_algorithm.empty_digest)
    end

    # The client's early traffic secret (`c e traffic`). Beryl never sends
    # or accepts 0-RTT data; this exists so RFC 8448 §4 can be checked.
    def client_early_traffic_secret(client_hello_digest : Bytes) : Bytes
      derive(@early_secret, "c e traffic", client_hello_digest)
    end

    # Mixes in the (EC)DHE shared secret and moves to the handshake stage.
    def enter_handshake_stage(shared_secret : Bytes) : Nil
      salt = derive(@early_secret, "derived", @hash_algorithm.empty_digest)
      @handshake_secret = @hash_algorithm.extract(shared_secret, salt: salt)
      Crypto::SecretWiping.wipe(salt)
      Crypto::SecretWiping.wipe(@early_secret)
    end

    # `c hs traffic`, over the transcript through the ServerHello.
    def client_handshake_traffic_secret(transcript_digest : Bytes) : Bytes
      derive(handshake_secret, "c hs traffic", transcript_digest)
    end

    # `s hs traffic`, over the transcript through the ServerHello.
    def server_handshake_traffic_secret(transcript_digest : Bytes) : Bytes
      derive(handshake_secret, "s hs traffic", transcript_digest)
    end

    # Moves to the master stage.
    def enter_master_stage : Nil
      current_handshake_secret = handshake_secret
      salt = derive(current_handshake_secret, "derived", @hash_algorithm.empty_digest)
      @master_secret = @hash_algorithm.extract(Bytes.new(@hash_algorithm.bytesize), salt: salt)
      Crypto::SecretWiping.wipe(salt)
      Crypto::SecretWiping.wipe(current_handshake_secret)
      @handshake_secret = nil
    end

    # `c ap traffic`, over the transcript through the server Finished.
    def client_application_traffic_secret(transcript_digest : Bytes) : Bytes
      derive(master_secret, "c ap traffic", transcript_digest)
    end

    # `s ap traffic`, over the transcript through the server Finished.
    def server_application_traffic_secret(transcript_digest : Bytes) : Bytes
      derive(master_secret, "s ap traffic", transcript_digest)
    end

    # `exp master`, over the transcript through the server Finished.
    def exporter_master_secret(transcript_digest : Bytes) : Bytes
      derive(master_secret, "exp master", transcript_digest)
    end

    # `res master`, over the transcript through the client Finished.
    def resumption_master_secret(transcript_digest : Bytes) : Bytes
      derive(master_secret, "res master", transcript_digest)
    end

    # Wipes whatever stage secret is still held.
    def wipe : Nil
      Crypto::SecretWiping.wipe(@early_secret)
      @handshake_secret.try { |secret| Crypto::SecretWiping.wipe(secret) }
      @master_secret.try { |secret| Crypto::SecretWiping.wipe(secret) }
      @handshake_secret = nil
      @master_secret = nil
    end

    # Returns the AEAD key and IV of a traffic secret (§7.3).
    def self.traffic_key_and_iv(hash_algorithm : HashAlgorithm, traffic_secret : Bytes, key_bytesize : Int32) : {Bytes, Bytes}
      {
        expand_label(hash_algorithm, traffic_secret, "key", Bytes.empty, key_bytesize),
        expand_label(hash_algorithm, traffic_secret, "iv", Bytes.empty, IV_BYTESIZE),
      }
    end

    # Returns the Finished key of a traffic secret (§4.4.4).
    def self.finished_key(hash_algorithm : HashAlgorithm, base_key : Bytes) : Bytes
      expand_label(hash_algorithm, base_key, "finished", Bytes.empty, hash_algorithm.bytesize)
    end

    # Returns the Finished verify_data over *transcript_digest* (§4.4.4).
    def self.finished_verify_data(hash_algorithm : HashAlgorithm, base_key : Bytes, transcript_digest : Bytes) : Bytes
      finished_key = finished_key(hash_algorithm, base_key)
      verify_data = hash_algorithm.authenticate(transcript_digest, key: finished_key)
      Crypto::SecretWiping.wipe(finished_key)
      verify_data
    end

    # Returns whether *verify_data* is the Finished value over
    # *transcript_digest*, compared in constant time.
    def self.finished_matches?(hash_algorithm : HashAlgorithm, base_key : Bytes, transcript_digest : Bytes, verify_data : Bytes) : Bool
      finished_key = finished_key(hash_algorithm, base_key)
      matches = hash_algorithm.verify(transcript_digest, verify_data, key: finished_key)
      Crypto::SecretWiping.wipe(finished_key)
      matches
    end

    # Returns the next application traffic secret (`traffic upd`, §7.2).
    def self.next_application_traffic_secret(hash_algorithm : HashAlgorithm, traffic_secret : Bytes) : Bytes
      expand_label(hash_algorithm, traffic_secret, "traffic upd", Bytes.empty, hash_algorithm.bytesize)
    end

    # Returns the PSK a NewSessionTicket stands for (§4.6.1).
    def self.resumption_pre_shared_key(hash_algorithm : HashAlgorithm, resumption_master_secret : Bytes, ticket_nonce : Bytes) : Bytes
      expand_label(hash_algorithm, resumption_master_secret, "resumption", ticket_nonce, hash_algorithm.bytesize)
    end

    # Returns the exported keying material (§7.5).
    def self.export_keying_material(hash_algorithm : HashAlgorithm, exporter_master_secret : Bytes, label : String,
                                    context : Bytes, bytesize : Int32) : Bytes
      secret = derive_secret(hash_algorithm, exporter_master_secret, label, hash_algorithm.empty_digest)
      material = expand_label(hash_algorithm, secret, "exporter", hash_algorithm.digest(context), bytesize)
      Crypto::SecretWiping.wipe(secret)
      material
    end

    private def derive(secret : Bytes, label : String, transcript_digest : Bytes) : Bytes
      KeySchedule.derive_secret(@hash_algorithm, secret, label, transcript_digest)
    end

    private def handshake_secret : Bytes
      @handshake_secret || raise Error.new("the key schedule has not reached the handshake stage")
    end

    private def master_secret : Bytes
      @master_secret || raise Error.new("the key schedule has not reached the master stage")
    end
  end
end
