module Amber::Beryl::TLS
  # The record content types (RFC 9846 §5.1).
  enum ContentType : UInt8
    Invalid          =  0
    ChangeCipherSpec = 20
    Alert            = 21
    Handshake        = 22
    ApplicationData  = 23
  end

  # The handshake message types (RFC 9846 §4). `MessageHash` stands in
  # for the first ClientHello in the transcript after a HelloRetryRequest
  # (§4.4.1).
  enum HandshakeType : UInt8
    ClientHello         =   1
    ServerHello         =   2
    NewSessionTicket    =   4
    EndOfEarlyData      =   5
    EncryptedExtensions =   8
    Certificate         =  11
    CertificateRequest  =  13
    CertificateVerify   =  15
    Finished            =  20
    KeyUpdate           =  24
    MessageHash         = 254
  end

  # The extensions Beryl reads or writes (RFC 9846 §4.2, RFC 6066,
  # RFC 7301, RFC 8449). Any other value is carried as an unknown
  # extension and ignored where RFC 9846 allows it.
  enum ExtensionType : UInt16
    ServerName                          =     0
    MaxFragmentLength                   =     1
    StatusRequest                       =     5
    SupportedGroups                     =    10
    SignatureAlgorithms                 =    13
    UseSrtp                             =    14
    Heartbeat                           =    15
    ApplicationLayerProtocolNegotiation =    16
    SignedCertificateTimestamp          =    18
    ClientCertificateType               =    19
    ServerCertificateType               =    20
    Padding                             =    21
    ExtendedMasterSecret                =    23
    RecordSizeLimit                     =    28
    SessionTicket                       =    35
    PreSharedKey                        =    41
    EarlyData                           =    42
    SupportedVersions                   =    43
    Cookie                              =    44
    PskKeyExchangeModes                 =    45
    CertificateAuthorities              =    47
    OidFilters                          =    48
    PostHandshakeAuth                   =    49
    SignatureAlgorithmsCert             =    50
    KeyShare                            =    51
    RenegotiationInfo                   = 65281
  end

  # The TLS 1.3 cipher suites (RFC 9846 §B.4). Beryl offers the first
  # three, in this order (plan §2).
  enum CipherSuite : UInt16
    TLS_AES_128_GCM_SHA256       = 0x1301
    TLS_AES_256_GCM_SHA384       = 0x1302
    TLS_CHACHA20_POLY1305_SHA256 = 0x1303

    # Returns the hash the key schedule runs on.
    def hash_algorithm : HashAlgorithm
      tls_aes_256_gcm_sha384? ? HashAlgorithm::SHA384 : HashAlgorithm::SHA256
    end

    # Returns the AEAD key size in bytes.
    def key_bytesize : Int32
      tls_aes_128_gcm_sha256? ? 16 : 32
    end

    # Returns a new AEAD keyed with *key*.
    def build_authenticated_encryption(key : Bytes) : Crypto::V1::AuthenticatedEncryption
      if tls_chacha20_poly1305_sha256?
        Crypto::V1::ChaCha20Poly1305.new(key)
      else
        Crypto::V1::AESGCM.new(key)
      end
    end

    # Returns whether *value* names one of the three suites.
    def self.supported_value?(value : UInt16) : Bool
      value.in?(0x1301_u16, 0x1302_u16, 0x1303_u16)
    end
  end

  # The key exchange groups Beryl uses (RFC 9846 §4.2.7). Other values are
  # read and skipped.
  enum NamedGroup : UInt16
    Secp256r1 = 0x0017
    Secp384r1 = 0x0018
    Secp521r1 = 0x0019
    X25519    = 0x001D
    X448      = 0x001E

    # Returns whether Beryl can run a key exchange on *value*.
    def self.supported_value?(value : UInt16) : Bool
      value == 0x001D_u16 || value == 0x0017_u16
    end
  end

  # The signature schemes of RFC 9846 §4.2.3 that Beryl offers or reads.
  enum SignatureScheme : UInt16
    RsaPkcs1Sha256       = 0x0401
    RsaPkcs1Sha384       = 0x0501
    RsaPkcs1Sha512       = 0x0601
    EcdsaSecp256r1Sha256 = 0x0403
    EcdsaSecp384r1Sha384 = 0x0503
    EcdsaSecp521r1Sha512 = 0x0603
    RsaPssRsaeSha256     = 0x0804
    RsaPssRsaeSha384     = 0x0805
    RsaPssRsaeSha512     = 0x0806
    Ed25519              = 0x0807
    Ed448                = 0x0808
    RsaPssPssSha256      = 0x0809
    RsaPssPssSha384      = 0x080a
    RsaPssPssSha512      = 0x080b
    RsaPkcs1Sha1         = 0x0201
    EcdsaSha1            = 0x0203
  end

  # The legacy and current protocol version numbers.
  module ProtocolVersion
    TLS_1_0 = 0x0301_u16
    TLS_1_2 = 0x0303_u16
    TLS_1_3 = 0x0304_u16
  end

  # The pre-shared key exchange modes (RFC 9846 §4.2.9). Beryl uses only
  # `PskDheKe`, so every resumed session still has forward secrecy.
  enum PskKeyExchangeMode : UInt8
    PskKe    = 0
    PskDheKe = 1
  end

  # The alert levels (RFC 9846 §6).
  enum AlertLevel : UInt8
    Warning = 1
    Fatal   = 2
  end

  # The alert descriptions (RFC 9846 §6).
  enum AlertDescription : UInt8
    CloseNotify                  =   0
    UnexpectedMessage            =  10
    BadRecordMac                 =  20
    RecordOverflow               =  22
    HandshakeFailure             =  40
    BadCertificate               =  42
    UnsupportedCertificate       =  43
    CertificateRevoked           =  44
    CertificateExpired           =  45
    CertificateUnknown           =  46
    IllegalParameter             =  47
    UnknownCa                    =  48
    AccessDenied                 =  49
    DecodeError                  =  50
    DecryptError                 =  51
    ProtocolVersion              =  70
    InsufficientSecurity         =  71
    InternalError                =  80
    InappropriateFallback        =  86
    UserCanceled                 =  90
    MissingExtension             = 109
    UnsupportedExtension         = 110
    UnrecognizedName             = 112
    BadCertificateStatusResponse = 113
    UnknownPskIdentity           = 115
    CertificateRequired          = 116
    NoApplicationProtocol        = 120
  end

  # The KeyUpdate request values (RFC 9846 §4.6.3).
  enum KeyUpdateRequest : UInt8
    UpdateNotRequested = 0
    UpdateRequested    = 1
  end
end
