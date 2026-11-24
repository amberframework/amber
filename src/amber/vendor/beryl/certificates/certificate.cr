require "../encoding/distinguished_encoding_rules"
require "../encoding/privacy_enhanced_mail"
require "./error"
require "./object_identifiers"
require "./distinguished_name"
require "./general_name"
require "./extensions"
require "./subject_public_key"

module Amber::Beryl::Certificates
  # An X.509 certificate (RFC 5280 §4.1), read from DER.
  #
  # ```
  # certificate = Amber::Beryl::Certificates::Certificate.new(der_bytes)
  # certificate.subject.to_s      # => "CN=example.com"
  # certificate.list_of_dns_names # => ["example.com"]
  # certificate.not_after         # => 2027-01-01 00:00:00 UTC
  # ```
  #
  # Reading checks the whole structure strictly (DER, every field of the
  # signed part, the contents of every extension Beryl knows, no extension
  # twice, the signature algorithm equal inside and outside the signed
  # part) and raises `MalformedCertificate` on any violation. Whether the
  # certificate may be used for anything is the job of `ChainVerification`.
  class Certificate
    alias DER = Encoding::DER

    # The whole certificate encoding.
    getter encoded : Bytes
    # The signed part (TBSCertificate), the bytes the signature covers.
    getter to_be_signed : Bytes
    # 1, 2 or 3.
    getter version : Int32
    # The serial number's two's-complement contents.
    getter serial_number : Bytes
    getter signature_algorithm : SignatureAlgorithm
    getter signature : Bytes
    getter issuer : DistinguishedName
    getter subject : DistinguishedName
    getter not_before : Time
    getter not_after : Time
    getter subject_public_key_info : SubjectPublicKeyInfo
    getter list_of_extensions : Array(Extension)

    getter basic_constraints : BasicConstraints?
    getter key_usage : KeyUsage?
    getter list_of_extended_key_usages : Array(DER::ObjectIdentifier)?
    getter list_of_subject_alternative_names : Array(GeneralName)?
    getter name_constraints : NameConstraints?
    getter authority_key_identifier : AuthorityKeyIdentifier?
    getter subject_key_identifier : Bytes?
    getter policy_constraints : PolicyConstraints?
    # The number of access descriptions in the authority information access
    # extension, or `nil` without one.
    getter authority_information_access_count : Int32?

    # The extension identifiers Beryl reads and acts on, or knows to be safe
    # to accept when marked critical: a critical extension outside this set
    # makes the certificate unusable (RFC 5280 §4.2).
    LIST_OF_UNDERSTOOD_EXTENSIONS = [
      ObjectIdentifiers::BASIC_CONSTRAINTS, ObjectIdentifiers::KEY_USAGE, ObjectIdentifiers::EXTENDED_KEY_USAGE,
      ObjectIdentifiers::SUBJECT_ALTERNATIVE_NAME, ObjectIdentifiers::NAME_CONSTRAINTS,
      ObjectIdentifiers::AUTHORITY_KEY_IDENTIFIER, ObjectIdentifiers::SUBJECT_KEY_IDENTIFIER,
      ObjectIdentifiers::CERTIFICATE_POLICIES, ObjectIdentifiers::POLICY_CONSTRAINTS,
      ObjectIdentifiers::AUTHORITY_INFORMATION_ACCESS,
    ]

    # Reads the DER certificate in *encoded*. Raises `MalformedCertificate`.
    def initialize(encoded : Bytes, *, limits : DER::Limits = DER::Limits.new)
      @encoded = encoded
      @to_be_signed = Bytes.empty
      @version = 1
      @serial_number = Bytes.empty
      @signature = Bytes.empty
      @not_before = Time::UNIX_EPOCH
      @not_after = Time::UNIX_EPOCH
      @list_of_extensions = [] of Extension
      @issuer = @subject = DistinguishedName.new(Bytes.empty, [] of Array(DistinguishedName::Attribute))
      @subject_public_key_info = SubjectPublicKeyInfo.new(ObjectIdentifiers::ED25519, nil, Bytes.empty, Bytes.empty)
      @signature_algorithm = SignatureAlgorithm.new(SignatureAlgorithm::Scheme::Unsupported, SignatureAlgorithm::HashFunction::None, Bytes.empty, ObjectIdentifiers::ED25519)
      begin
        read_certificate(encoded, limits)
      rescue error : Encoding::Error
        raise MalformedCertificate.new("the certificate is malformed: #{error.message}")
      end
    end

    private def read_certificate(encoded : Bytes, limits : DER::Limits) : Nil
      reader = DER::Reader.new(encoded, limits)
      outer = reader.read_element(DER::SEQUENCE)
      reader.finish

      @to_be_signed = Bytes.empty
      @version = 1
      @serial_number = Bytes.empty
      @signature = Bytes.empty
      @not_before = Time::UNIX_EPOCH
      @not_after = Time::UNIX_EPOCH
      @list_of_extensions = [] of Extension
      inner_signature_algorithm = nil
      issuer = nil
      subject = nil
      public_key_info = nil
      outer_signature_algorithm = nil

      reader.enter(outer) do |certificate|
        to_be_signed_element = certificate.read_element(DER::SEQUENCE)
        @to_be_signed = to_be_signed_element.encoded
        certificate.enter(to_be_signed_element) do |fields|
          explicit_version = fields.read_optional_element(DER::Tag.context_specific(0, is_constructed: true))
          if explicit_version
            @version = 1 + fields.enter(explicit_version, &.read_small_integer).to_i32
            # DER omits a DEFAULT, so an explicit v1 is not DER.
            raise DER_ERROR.new("an explicit version 1", explicit_version.offset) unless 2 <= @version <= 3
          end
          @serial_number = fields.read_integer_bytes
          inner_signature_algorithm = SignatureAlgorithm.read(fields)
          issuer = DistinguishedName.read(fields)
          fields.read_sequence do |validity|
            @not_before = validity.read_time
            @not_after = validity.read_time
          end
          subject = DistinguishedName.read(fields)
          public_key_info = SubjectPublicKeyInfo.read(fields)
          {1_u32, 2_u32}.each do |number|
            unique_identifier = fields.read_optional_element(DER::Tag.context_specific(number, is_constructed: false))
            next unless unique_identifier
            raise DER_ERROR.new("a unique identifier in a version 1 certificate", unique_identifier.offset) if @version == 1
            DER.decode_bit_string(unique_identifier)
          end
          if extensions_element = fields.read_optional_element(DER::Tag.context_specific(3, is_constructed: true))
            raise DER_ERROR.new("extensions in a certificate older than version 3", extensions_element.offset) unless @version == 3
            fields.enter(extensions_element) do |explicit|
              explicit.read_sequence do |sequence|
                raise DER_ERROR.new("an empty extensions list", extensions_element.offset) if sequence.at_end?
                until sequence.at_end?
                  @list_of_extensions << Certificate.read_extension(sequence)
                end
              end
            end
          end
        end
        outer_signature_algorithm = SignatureAlgorithm.read(certificate)
        @signature = certificate.read_byte_aligned_bit_string
      end

      @issuer = issuer || raise DER_ERROR.new("no issuer")
      @subject = subject || raise DER_ERROR.new("no subject")
      @subject_public_key_info = public_key_info || raise DER_ERROR.new("no subject public key")
      @signature_algorithm = outer_signature_algorithm || raise DER_ERROR.new("no signature algorithm")
      unless inner_signature_algorithm.try(&.encoded) == @signature_algorithm.encoded
        raise MalformedCertificate.new("the signature algorithm differs inside and outside the signed part (RFC 5280 §4.1.1.2)")
      end
      decode_extensions(reader)
    end

    private DER_ERROR = Encoding::MalformedEncoding

    # Reads every `CERTIFICATE` block of the PEM *text*.
    def self.list_from_pem(text : String) : Array(Certificate)
      Encoding::PEM.decode(text, label: "CERTIFICATE").map { |der| Certificate.new(der) }
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the PEM text is malformed: #{error.message}")
    end

    # :nodoc:
    def self.read_extension(reader : DER::Reader) : Extension
      element = reader.read_element(DER::SEQUENCE)
      reader.enter(element) do |sequence|
        identifier = sequence.read_object_identifier
        is_critical = sequence.next_is?(DER::BOOLEAN) ? sequence.read_boolean : false
        value = sequence.read_octet_string
        Extension.new(identifier, is_critical, value, element)
      end
    end

    private def decode_extensions(reader : DER::Reader) : Nil
      seen = Set(DER::ObjectIdentifier).new
      @list_of_extensions.each do |extension|
        unless seen.add?(extension.identifier)
          raise DER_ERROR.new("the extension #{extension.identifier} appears twice (RFC 5280 §4.2)", extension.element.offset)
        end
        reader.enter_encapsulated(extension.element, extension.value) do |contents|
          case extension.identifier
          when ObjectIdentifiers::BASIC_CONSTRAINTS        then @basic_constraints = ExtensionDecoding.basic_constraints(contents)
          when ObjectIdentifiers::KEY_USAGE                then @key_usage = ExtensionDecoding.key_usage(contents)
          when ObjectIdentifiers::EXTENDED_KEY_USAGE       then @list_of_extended_key_usages = ExtensionDecoding.extended_key_usage(contents)
          when ObjectIdentifiers::SUBJECT_ALTERNATIVE_NAME then @list_of_subject_alternative_names = ExtensionDecoding.subject_alternative_names(contents)
          when ObjectIdentifiers::NAME_CONSTRAINTS         then @name_constraints = ExtensionDecoding.name_constraints(contents)
          when ObjectIdentifiers::AUTHORITY_KEY_IDENTIFIER then @authority_key_identifier = ExtensionDecoding.authority_key_identifier(contents)
          when ObjectIdentifiers::SUBJECT_KEY_IDENTIFIER   then @subject_key_identifier = ExtensionDecoding.subject_key_identifier(contents)
          when ObjectIdentifiers::POLICY_CONSTRAINTS       then @policy_constraints = ExtensionDecoding.policy_constraints(contents)
          when ObjectIdentifiers::CERTIFICATE_POLICIES     then ExtensionDecoding.certificate_policies(contents)
          when ObjectIdentifiers::AUTHORITY_INFORMATION_ACCESS
            @authority_information_access_count = ExtensionDecoding.information_access(contents)
          when ObjectIdentifiers::CRL_DISTRIBUTION_POINTS, ObjectIdentifiers::FRESHEST_CRL
            ExtensionDecoding.distribution_points(contents)
          when ObjectIdentifiers::ISSUER_ALTERNATIVE_NAME
            GeneralName.read_list(contents)
          else
            # Not interpreted: the contents must still be DER (RFC 5280
            # §4.1 says extnValue holds a DER encoding).
            until contents.at_end?
              contents.check_universal_contents(contents.read_element)
            end
          end
        end
      end
    end

    # The extension with *identifier*, or `nil`.
    def extension(identifier : DER::ObjectIdentifier) : Extension?
      @list_of_extensions.find { |extension| extension.identifier == identifier }
    end

    # Returns whether an extension marked critical is outside
    # `LIST_OF_UNDERSTOOD_EXTENSIONS`.
    def has_unknown_critical_extension? : Bool
      @list_of_extensions.any? { |extension| extension.is_critical && !LIST_OF_UNDERSTOOD_EXTENSIONS.includes?(extension.identifier) }
    end

    # Returns whether the subject and issuer names are the same (RFC 5280
    # §6.1: a self-issued certificate).
    def self_issued? : Bool
      @subject == @issuer
    end

    # Returns whether basic constraints mark this a CA certificate.
    def certificate_authority? : Bool
      @basic_constraints.try(&.is_certificate_authority) || false
    end

    # The DNS names among the subject alternative names, as text.
    def list_of_dns_names : Array(String)
      (@list_of_subject_alternative_names || [] of GeneralName).select(&.kind.domain_name?).map(&.text)
    end

    # The IP addresses among the subject alternative names, as bytes.
    def list_of_ip_addresses : Array(Bytes)
      (@list_of_subject_alternative_names || [] of GeneralName).select(&.kind.internet_protocol_address?).map(&.value)
    end

    # Returns whether *time* is within notBefore and notAfter, both
    # inclusive (RFC 5280 §4.1.2.5). Fractions of a second in *time* are
    # dropped first, since certificate times have whole seconds.
    def valid_at?(time : Time) : Bool
      whole_seconds = Time.unix(time.to_unix)
      @not_before <= whole_seconds <= @not_after
    end

    # Returns whether *issuer_key* verifies this certificate's signature.
    def signed_by?(issuer_key : VerificationKey) : Bool
      @signature_algorithm.verify(issuer_key, @to_be_signed, @signature)
    end

    def ==(other : Certificate) : Bool
      @encoded == other.encoded
    end

    def hash(hasher)
      @encoded.hash(hasher)
    end

    def to_pem : String
      Encoding::PEM.encode(@encoded, label: "CERTIFICATE")
    end

    def to_s(io : IO) : Nil
      io << "#<Amber::Beryl::Certificates::Certificate subject=\"" << @subject << "\">"
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end
end
