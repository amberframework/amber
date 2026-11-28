module Amber::Beryl::TLS
  # Whether a server asks the client for a certificate (RFC 9846 §4.3.2),
  # and what it does when the client sends none. Set through
  # `Context::Server#client_verify_mode=`, or `Context::Server#verify_mode=`
  # as `OpenSSL::SSL::Context::Server` takes it.
  enum ClientVerifyMode
    # No CertificateRequest is sent (the default).
    None
    # A CertificateRequest is sent. A chain the client sends is verified
    # and its CertificateVerify checked; an empty Certificate is accepted
    # and the connection has no peer certificate.
    Optional
    # A CertificateRequest is sent, and an empty Certificate ends the
    # handshake with the certificate_required alert (§4.4.2.4).
    Required

    # Returns whether the server sends a CertificateRequest.
    def requests_certificate? : Bool
      !none?
    end
  end
end
