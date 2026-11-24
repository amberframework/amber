require "./certificate"

module Amber::Beryl::Certificates
  # A certificate revocation list (RFC 5280 §5), read from DER.
  #
  # `ChainVerification` takes CRLs the caller already has (Beryl does not
  # fetch them). A CRL counts for a certificate when its issuer name is the
  # certificate's issuer name; such a CRL must then be usable (signed by the
  # issuer's key, current at the validation time, no unknown critical
  # extension, a non-critical CRL number, no serial listed twice), or the
  # chain is refused, since a CRL that claims to speak for an issuer and
  # cannot be checked must not be ignored.
  class CertificateRevocationList
    alias DER = Encoding::DER

    # One revoked certificate.
    record Entry, serial_number : Bytes, revocation_date : Time, list_of_extensions : Array(Extension)

    # The extension identifiers a CRL may mark critical and still be used.
    LIST_OF_UNDERSTOOD_EXTENSIONS = [ObjectIdentifiers::AUTHORITY_KEY_IDENTIFIER, ObjectIdentifiers::CRL_NUMBER]
    # The entry extension identifiers an entry may mark critical.
    LIST_OF_UNDERSTOOD_ENTRY_EXTENSIONS = [ObjectIdentifiers::CRL_REASON, ObjectIdentifiers::INVALIDITY_DATE]

    # CRLs hold one entry per revoked certificate, so they are allowed to be
    # larger than one certificate: 16 MiB, about 400,000 entries.
    DEFAULT_LIMITS = DER::Limits.new(largest_input_bytesize: 16 * 1024 * 1024)

    getter encoded : Bytes
    getter to_be_signed : Bytes
    getter signature_algorithm : SignatureAlgorithm
    getter signature : Bytes
    getter issuer : DistinguishedName
    getter this_update : Time
    getter next_update : Time?
    getter list_of_entries : Array(Entry)
    getter list_of_extensions : Array(Extension)

    # Reads the DER CRL in *encoded*. Raises `MalformedCertificate`.
    def initialize(encoded : Bytes, *, limits : DER::Limits = DEFAULT_LIMITS)
      @encoded = encoded
      @to_be_signed = Bytes.empty
      @signature = Bytes.empty
      @issuer = DistinguishedName.new(Bytes.empty, [] of Array(DistinguishedName::Attribute))
      @this_update = Time::UNIX_EPOCH
      @list_of_entries = [] of Entry
      @list_of_extensions = [] of Extension
      @signature_algorithm = SignatureAlgorithm.new(SignatureAlgorithm::Scheme::Unsupported, SignatureAlgorithm::HashFunction::None, Bytes.empty, ObjectIdentifiers::ED25519)
      begin
        read_list(encoded, limits)
      rescue error : Encoding::Error
        raise MalformedCertificate.new("the CRL is malformed: #{error.message}")
      end
    end

    private def read_list(encoded : Bytes, limits : DER::Limits) : Nil
      reader = DER::Reader.new(encoded, limits)
      to_be_signed = Bytes.empty
      inner_algorithm = nil
      outer_algorithm = nil
      issuer = nil
      this_update = nil
      next_update = nil
      signature = Bytes.empty
      list_of_entries = [] of Entry
      list_of_extensions = [] of Extension

      reader.read_sequence do |certificate_list|
        to_be_signed_element = certificate_list.read_element(DER::SEQUENCE)
        to_be_signed = to_be_signed_element.encoded
        certificate_list.enter(to_be_signed_element) do |fields|
          if fields.next_is?(DER::INTEGER)
            version = fields.read_small_integer
            raise Encoding::MalformedEncoding.new("a CRL version other than v2") unless version == 1
          end
          inner_algorithm = SignatureAlgorithm.read(fields)
          issuer = DistinguishedName.read(fields)
          this_update = fields.read_time
          next_tag = fields.peek_tag
          if next_tag == DER::UTC_TIME || next_tag == DER::GENERALIZED_TIME
            next_update = fields.read_time
          end
          if fields.next_is?(DER::SEQUENCE)
            fields.read_sequence do |revoked|
              until revoked.at_end?
                revoked_entry = revoked.read_sequence do |entry|
                  serial = entry.read_integer_bytes
                  date = entry.read_time
                  entry_extensions = [] of Extension
                  unless entry.at_end?
                    entry.read_sequence do |extensions|
                      until extensions.at_end?
                        entry_extensions << Certificate.read_extension(extensions)
                      end
                    end
                  end
                  Entry.new(serial, date, entry_extensions)
                end
                list_of_entries << revoked_entry
              end
            end
          end
          if explicit = fields.read_optional_element(DER::Tag.context_specific(0, is_constructed: true))
            fields.enter(explicit) do |inner|
              inner.read_sequence do |extensions|
                until extensions.at_end?
                  list_of_extensions << Certificate.read_extension(extensions)
                end
              end
            end
          end
        end
        outer_algorithm = SignatureAlgorithm.read(certificate_list)
        signature = certificate_list.read_byte_aligned_bit_string
      end
      reader.finish

      @to_be_signed = to_be_signed
      @signature = signature
      @issuer = issuer || raise MalformedCertificate.new("the CRL has no issuer")
      @this_update = this_update || raise MalformedCertificate.new("the CRL has no thisUpdate")
      @next_update = next_update
      @list_of_entries = list_of_entries
      @list_of_extensions = list_of_extensions
      @signature_algorithm = outer_algorithm || raise MalformedCertificate.new("the CRL has no signature algorithm")
      unless inner_algorithm.try(&.encoded) == @signature_algorithm.encoded
        raise MalformedCertificate.new("the CRL's signature algorithm differs inside and outside the signed part")
      end
    end

    # Reads every `X509 CRL` block of the PEM *text*.
    def self.list_from_pem(text : String) : Array(CertificateRevocationList)
      Encoding::PEM.decode(text, label: "X509 CRL").map { |der| CertificateRevocationList.new(der) }
    rescue error : Encoding::Error
      raise MalformedCertificate.new("the PEM text is malformed: #{error.message}")
    end

    # Returns why this CRL cannot be used to decide revocation for
    # certificates of *issuer_certificate* at *time*, or `nil` when it can.
    def unusable_reason(issuer_certificate : Certificate, time : Time) : String?
      key = issuer_certificate.subject_public_key_info.verification_key
      return "the CRL issuer's key is not usable" unless key
      return "the CRL's signature does not verify under the issuer's key" unless @signature_algorithm.verify(key, @to_be_signed, @signature)
      if key_usage = issuer_certificate.key_usage
        return "the CRL issuer's key usage lacks cRLSign (RFC 5280 §6.3.3)" unless key_usage.crl_sign?
      end

      whole_seconds = Time.unix(time.to_unix)
      return "the CRL is not yet in effect (thisUpdate is after the validation time)" if @this_update > whole_seconds
      if next_update = @next_update
        return "the CRL is out of date (nextUpdate is before the validation time)" if next_update < whole_seconds
      end

      crl_number = @list_of_extensions.find { |extension| extension.identifier == ObjectIdentifiers::CRL_NUMBER }
      return "the CRL has no CRL number (RFC 5280 §5.2.3)" unless crl_number
      return "the CRL number is marked critical (RFC 5280 §5.2.3)" if crl_number.is_critical
      if @list_of_extensions.any? { |extension| extension.is_critical && !LIST_OF_UNDERSTOOD_EXTENSIONS.includes?(extension.identifier) }
        return "the CRL has an unknown critical extension (RFC 5280 §5.2)"
      end

      seen = Set(Bytes).new
      @list_of_entries.each do |entry|
        return "the CRL lists a serial number twice" unless seen.add?(entry.serial_number)
        if entry.list_of_extensions.any? { |extension| extension.is_critical && !LIST_OF_UNDERSTOOD_ENTRY_EXTENSIONS.includes?(extension.identifier) }
          return "a CRL entry has an unknown critical extension (RFC 5280 §5.3)"
        end
      end
      nil
    end

    # Returns whether the CRL lists *serial_number*.
    def revokes?(serial_number : Bytes) : Bool
      @list_of_entries.any? { |entry| entry.serial_number == serial_number }
    end
  end
end
