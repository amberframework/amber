require "./encoding"
require "./certificates/error"
require "./certificates/certificate"
require "./certificates/certificate_revocation_list"
require "./certificates/service_identity"
require "./certificates/public_suffix_list"
require "./certificates/name_constraint_check"
require "./certificates/trust_store"
require "./certificates/chain_verification"
require "./certificates/private_key_file"

# X.509 certificates and certificate path validation, written in Crystal.
#
# The calls on this module use the choices Beryl recommends: the pinned
# Mozilla root set, the current time and the `serverAuth` purpose.
#
# ```
# chain = Amber::Beryl::Certificates.read_pem_chain(File.read("chain.pem"))
# Amber::Beryl::Certificates.verify_server_chain(chain, hostname: "example.com") # => the verified path, or raises
# key = Amber::Beryl::Certificates.read_private_key(File.read("server.key"))
# ```
#
# `ChainVerification` takes another trust store (`TrustStore.system`,
# `TrustStore.from_pem`), a validation time, a client purpose, CRLs and
# limits. See `docs/certificates.md` for the profile it enforces and the
# test suites behind it.
module Amber::Beryl::Certificates
  # Reads every certificate of the PEM *text*, in order (the leaf first, as
  # TLS servers and `chain.pem` files hold them).
  def self.read_pem_chain(text : String) : Array(Certificate)
    Certificate.list_from_pem(text)
  end

  # Verifies *chain* (the leaf first, then the intermediates in any order)
  # for a TLS server named *hostname* (a DNS name or an IP address), against
  # the Mozilla root set at the current time. Returns the verified path,
  # leaf first, or raises `VerificationFailed`.
  def self.verify_server_chain(chain : Array(Certificate), *, hostname : String, trust_store : TrustStore = TrustStore.mozilla) : Array(Certificate)
    leaf = chain.first? || raise VerificationFailed.new(FailureReason::MalformedLeaf, "the chain is empty")
    ChainVerification.new(trust_store).verify(leaf, chain[1..], identity: ServiceIdentity.new(hostname))
  end

  # Reads the first private key in the PEM *text* (PKCS #8, SEC 1 or
  # PKCS #1).
  def self.read_private_key(text : String) : SigningKey
    PrivateKeyFile.read_pem(text)
  end
end
