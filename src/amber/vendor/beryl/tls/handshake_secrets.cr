require "../crypto/secret_wiping"
require "./key_schedule"

module Amber::Beryl::TLS
  # :nodoc:
  #
  # The secrets one handshake derives, kept so that all of them are wiped
  # however the handshake ends. Those it only `held` are wiped when it
  # ends; those it `handed_on` to the connection are wiped only when it
  # failed, since a finished connection owns them and wipes them at close.
  class HandshakeSecrets
    @list_of_held_secrets = [] of Bytes
    @list_of_held_schedules = [] of KeySchedule
    @list_of_handed_on_secrets = [] of Bytes
    @is_complete = false

    # Records *secret* as one the handshake alone uses, and returns it.
    def held(secret : Bytes) : Bytes
      @list_of_held_secrets << secret
      secret
    end

    # Records *schedule* as one the handshake alone uses, and returns it.
    def held(schedule : KeySchedule) : KeySchedule
      @list_of_held_schedules << schedule
      schedule
    end

    # Records *secret* as one the finished handshake hands to the
    # connection, and returns it.
    def handed_on(secret : Bytes) : Bytes
      @list_of_handed_on_secrets << secret
      secret
    end

    # Marks the handshake finished: the handed-on secrets now belong to
    # the connection.
    def complete : Nil
      @is_complete = true
    end

    # Wipes every held secret, and the handed-on ones unless the handshake
    # finished.
    def wipe : Nil
      @list_of_held_schedules.each(&.wipe)
      @list_of_held_secrets.each { |secret| Crypto::SecretWiping.wipe(secret) }
      @list_of_handed_on_secrets.each { |secret| Crypto::SecretWiping.wipe(secret) } unless @is_complete
      @list_of_held_schedules.clear
      @list_of_held_secrets.clear
      @list_of_handed_on_secrets.clear
    end
  end
end
