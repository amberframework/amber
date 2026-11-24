require "./certificate"

module Amber::Beryl::Certificates
  # The certificates a verifier trusts as the ends of paths (trust anchors).
  #
  # ```
  # Amber::Beryl::Certificates::TrustStore.mozilla                       # the pinned Mozilla root set
  # Amber::Beryl::Certificates::TrustStore.system                        # the operating system's bundle
  # Amber::Beryl::Certificates::TrustStore.from_pem(File.read("ca.pem")) # an application's own CA
  # ```
  #
  # `mozilla` is the Mozilla root set with the Websites trust bit, from the
  # CCADB report `IncludedRootsPEMTxt?TrustBitsInclude=Websites`, compiled
  # into Beryl and pinned by sha256 (`MOZILLA_ROOTS_SHA256`), so verdicts are
  # the same on every machine and change only with a Beryl release. Mozilla's
  # per-root "distrust for TLS after" dates are not applied.
  class TrustStore
    # The sha256 of `data/mozilla_root_certificates.pem`, checked by a spec.
    MOZILLA_ROOTS_SHA256 = "4d5d68b49a30f7a28efb573a9dce4fbe54a91dd99cf53419fbf783638e39b852"
    # When the root set was taken from the CCADB.
    MOZILLA_ROOTS_RETRIEVED = "2026-11-23"

    MOZILLA_ROOTS_PEM = {{ read_file("#{__DIR__}/data/mozilla_root_certificates.pem") }}

    # The bundles `system` reads, first one found wins: Debian and Ubuntu,
    # Fedora and RHEL, openSUSE, then Alpine and macOS (where Apple ships
    # and updates the system roots as `/etc/ssl/cert.pem`).
    LIST_OF_SYSTEM_BUNDLE_PATHS = [
      "/etc/ssl/certs/ca-certificates.crt",
      "/etc/pki/tls/certs/ca-bundle.crt",
      "/etc/ssl/ca-bundle.pem",
      "/etc/ssl/cert.pem",
    ]

    getter list_of_certificates : Array(Certificate)
    @by_subject : Hash(Bytes, Array(Certificate))

    def initialize(list_of_certificates : Enumerable(Certificate))
      @list_of_certificates = list_of_certificates.to_a.uniq
      @by_subject = Hash(Bytes, Array(Certificate)).new
      @list_of_certificates.each do |certificate|
        (@by_subject[certificate.subject.encoded] ||= [] of Certificate) << certificate
      end
    end

    class_getter mozilla : TrustStore { from_pem(MOZILLA_ROOTS_PEM) }

    # The trust anchors in the operating system's bundle (see
    # `LIST_OF_SYSTEM_BUNDLE_PATHS`). Raises `Error` when none is found.
    def self.system : TrustStore
      path = LIST_OF_SYSTEM_BUNDLE_PATHS.find { |candidate| File.exists?(candidate) }
      raise Error.new("no system certificate bundle found at #{LIST_OF_SYSTEM_BUNDLE_PATHS.join(", ")}") unless path
      from_pem(File.read(path))
    end

    # The certificates in the PEM *text*. A block that is not a certificate
    # Beryl can read is skipped (system bundles hold a few with old
    # encodings), and logged at debug level.
    def self.from_pem(text : String) : TrustStore
      list_of_certificates = [] of Certificate
      Encoding::PEM.decode(text, label: "CERTIFICATE").each do |der|
        list_of_certificates << Certificate.new(der)
      rescue error : MalformedCertificate
        Log.debug { "skipped a trust anchor that does not parse: #{error.message}" }
      end
      TrustStore.new(list_of_certificates)
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the PEM text is malformed: #{error.message}")
    end

    # The anchors whose subject is *name*.
    def list_of_anchors_named(name : DistinguishedName) : Array(Certificate)
      @by_subject[name.encoded]? || [] of Certificate
    end

    def includes?(certificate : Certificate) : Bool
      list_of_anchors_named(certificate.subject).includes?(certificate)
    end

    def size : Int32
      @list_of_certificates.size
    end
  end
end
