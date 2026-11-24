require "log"
require "../error"

module Amber::Beryl::Certificates
  Log = ::Log.for(self)

  # The base of every error raised by `Amber::Beryl::Certificates`.
  class Error < Amber::Beryl::Error
  end

  # Raised when bytes handed in as a certificate, a CRL or a key file are
  # not one: the DER is malformed, or the structure is not the one RFC 5280,
  # RFC 5958 or RFC 8017 defines.
  class MalformedCertificate < Error
  end

  # Raised when a private key file holds a key Beryl does not take: an
  # algorithm it has not built, or parts that do not belong together.
  class UnsupportedKey < Error
  end

  # Why a chain was refused. `VerificationFailed#reason` carries one.
  enum FailureReason
    # The leaf itself could not be read.
    MalformedLeaf
    # The leaf is outside its validity period at the validation time.
    LeafExpiredOrNotYetValid
    # The leaf breaks the profile: a CA certificate in leaf position, an
    # unknown critical extension, a missing subject alternative name.
    LeafProfileViolation
    # The leaf's extended key usage does not allow the purpose asked for.
    UsageNotAllowed
    # No subject alternative name of the leaf matches the name asked for.
    NameMismatch
    # No path from the leaf reaches a trust anchor that satisfies every
    # check; `VerificationFailed#message` names the last check that failed.
    NoTrustedPath
    # Path building stopped at its budget (candidates tried, signatures
    # checked, name comparisons, processor time).
    BudgetExceeded
    # A CRL handed in revokes a certificate of the path, or a CRL that
    # covers the path cannot be used.
    Revoked
    # More certificates, or more bytes, were presented than the limits allow.
    TooManyCertificates
  end

  # Raised when a certificate chain does not verify. `reason` says which
  # kind of check refused it and the message says which certificate and
  # which rule.
  class VerificationFailed < Error
    getter reason : FailureReason

    def initialize(@reason : FailureReason, message : String)
      super(message)
    end
  end
end
