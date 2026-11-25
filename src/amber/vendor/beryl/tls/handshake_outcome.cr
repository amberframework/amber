module Amber::Beryl::TLS
  # What a finished handshake hands to the connection: the suite, the
  # application traffic secrets, and what was negotiated.
  class HandshakeOutcome
    getter cipher_suite : CipherSuite
    getter client_application_traffic_secret : Bytes
    getter server_application_traffic_secret : Bytes
    getter exporter_master_secret : Bytes
    # The resumption master secret, for the tickets a server sends or a
    # client receives.
    getter resumption_master_secret : Bytes
    getter alpn_protocol : String?
    # The server name the client asked for (SNI).
    getter server_name : String?
    getter list_of_peer_certificates : Array(Certificates::Certificate)
    getter? resumed : Bool
    # The peer's record_size_limit, or nil when it sent none.
    getter peer_record_size_limit : Int32?
    # The negotiated group, or nil.
    getter group : NamedGroup?

    def initialize(@cipher_suite, @client_application_traffic_secret, @server_application_traffic_secret,
                   @exporter_master_secret, @resumption_master_secret, @alpn_protocol, @server_name,
                   @list_of_peer_certificates, @resumed, @peer_record_size_limit, @group)
    end
  end
end
