require "../encoding/distinguished_encoding_rules"

module Amber::Beryl::Certificates
  # The object identifiers the certificate code reads, named as their
  # standards name them.
  module ObjectIdentifiers
    alias OID = Encoding::DER::ObjectIdentifier

    # Public-key algorithms (RFC 8017, RFC 5480, RFC 8410).
    RSA_ENCRYPTION            = OID.parse("1.2.840.113549.1.1.1")
    RSASSA_PSS                = OID.parse("1.2.840.113549.1.1.10")
    ELLIPTIC_CURVE_PUBLIC_KEY = OID.parse("1.2.840.10045.2.1")
    ED25519                   = OID.parse("1.3.101.112")

    # Named curves (RFC 5480 §2.1.1.1).
    SECP256R1 = OID.parse("1.2.840.10045.3.1.7")
    SECP384R1 = OID.parse("1.3.132.0.34")

    # Signature algorithms (RFC 4055, RFC 5758, RFC 8410).
    SHA256_WITH_RSA_ENCRYPTION = OID.parse("1.2.840.113549.1.1.11")
    SHA384_WITH_RSA_ENCRYPTION = OID.parse("1.2.840.113549.1.1.12")
    SHA512_WITH_RSA_ENCRYPTION = OID.parse("1.2.840.113549.1.1.13")
    ECDSA_WITH_SHA256          = OID.parse("1.2.840.10045.4.3.2")
    ECDSA_WITH_SHA384          = OID.parse("1.2.840.10045.4.3.3")
    ECDSA_WITH_SHA512          = OID.parse("1.2.840.10045.4.3.4")

    # Hashes and MGF1, for RSASSA-PSS parameters (RFC 4055 §2.1).
    SHA256 = OID.parse("2.16.840.1.101.3.4.2.1")
    SHA384 = OID.parse("2.16.840.1.101.3.4.2.2")
    SHA512 = OID.parse("2.16.840.1.101.3.4.2.3")
    MGF1   = OID.parse("1.2.840.113549.1.1.8")

    # Certificate extensions (RFC 5280 §4.2).
    AUTHORITY_KEY_IDENTIFIER          = OID.parse("2.5.29.35")
    SUBJECT_KEY_IDENTIFIER            = OID.parse("2.5.29.14")
    KEY_USAGE                         = OID.parse("2.5.29.15")
    CERTIFICATE_POLICIES              = OID.parse("2.5.29.32")
    POLICY_MAPPINGS                   = OID.parse("2.5.29.33")
    SUBJECT_ALTERNATIVE_NAME          = OID.parse("2.5.29.17")
    ISSUER_ALTERNATIVE_NAME           = OID.parse("2.5.29.18")
    SUBJECT_DIRECTORY_ATTRIBUTES      = OID.parse("2.5.29.9")
    BASIC_CONSTRAINTS                 = OID.parse("2.5.29.19")
    NAME_CONSTRAINTS                  = OID.parse("2.5.29.30")
    POLICY_CONSTRAINTS                = OID.parse("2.5.29.36")
    EXTENDED_KEY_USAGE                = OID.parse("2.5.29.37")
    CRL_DISTRIBUTION_POINTS           = OID.parse("2.5.29.31")
    INHIBIT_ANY_POLICY                = OID.parse("2.5.29.54")
    FRESHEST_CRL                      = OID.parse("2.5.29.46")
    AUTHORITY_INFORMATION_ACCESS      = OID.parse("1.3.6.1.5.5.7.1.1")
    SUBJECT_INFORMATION_ACCESS        = OID.parse("1.3.6.1.5.5.7.1.11")
    TLS_FEATURE                       = OID.parse("1.3.6.1.5.5.7.1.24")
    SIGNED_CERTIFICATE_TIMESTAMP_LIST = OID.parse("1.3.6.1.4.1.11129.2.4.2")

    # CRL extensions (RFC 5280 §5.2 and §5.3).
    CRL_NUMBER                 = OID.parse("2.5.29.20")
    DELTA_CRL_INDICATOR        = OID.parse("2.5.29.27")
    ISSUING_DISTRIBUTION_POINT = OID.parse("2.5.29.28")
    CRL_REASON                 = OID.parse("2.5.29.21")
    INVALIDITY_DATE            = OID.parse("2.5.29.24")
    CERTIFICATE_ISSUER         = OID.parse("2.5.29.29")

    # Extended key usages (RFC 5280 §4.2.1.12).
    ANY_EXTENDED_KEY_USAGE = OID.parse("2.5.29.37.0")
    SERVER_AUTHENTICATION  = OID.parse("1.3.6.1.5.5.7.3.1")
    CLIENT_AUTHENTICATION  = OID.parse("1.3.6.1.5.5.7.3.2")

    # Name attributes (RFC 5280 Appendix A).
    COMMON_NAME   = OID.parse("2.5.4.3")
    EMAIL_ADDRESS = OID.parse("1.2.840.113549.1.9.1")
  end
end
