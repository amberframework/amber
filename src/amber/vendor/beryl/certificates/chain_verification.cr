require "./certificate"
require "./certificate_revocation_list"
require "./trust_store"
require "./service_identity"
require "./name_constraint_check"
require "./public_suffix_list"

module Amber::Beryl::Certificates
  # What the leaf certificate is to be used for: the extended key usage
  # a chain must allow (RFC 5280 §4.2.1.12).
  enum Purpose
    # A TLS server (`id-kp-serverAuth`).
    ServerAuthentication
    # A TLS client (`id-kp-clientAuth`).
    ClientAuthentication

    def object_identifier : Encoding::DER::ObjectIdentifier
      server_authentication? ? ObjectIdentifiers::SERVER_AUTHENTICATION : ObjectIdentifiers::CLIENT_AUTHENTICATION
    end
  end

  # Verifies a certificate chain: builds a path from the leaf through the
  # presented intermediates to a trust anchor and checks every rule of
  # RFC 5280 §6 and the web PKI profile along it.
  #
  # ```
  # verification = Amber::Beryl::Certificates::ChainVerification.new(Amber::Beryl::Certificates::TrustStore.mozilla)
  # path = verification.verify(leaf, intermediates, identity: Amber::Beryl::Certificates::ServiceIdentity.new("example.com"))
  # # => [leaf, intermediate, root], or raises VerificationFailed
  # ```
  #
  # Path building is depth first, trust anchors before intermediates, and
  # candidates whose subject key identifier matches the child's authority
  # key identifier before the others. Issuers are found by name: a leaf or
  # intermediate without an authority key identifier (common under private
  # CAs for PostgreSQL and MySQL) is matched to the certificates named as
  # its issuer, each tried by signature, as Go's crypto/x509 and OpenSSL do. A candidate that fails any check is
  # backed out of and the next one tried, so a chain that also offers an
  # expired or cross-signed intermediate still finds its good path. Cycles
  # are refused. The search is bounded by `Limits`.
  #
  # Every certificate on the path must satisfy (the profile that rustls-
  # webpki, Go and x509-limbo apply):
  # - version 3; no unknown critical extension; the authority and subject
  #   key identifiers, authority information access and policy constraints
  #   marked as RFC 5280 requires; a non-empty issuer; below the anchor, a
  #   serial number that is positive and at most 20 bytes (some Mozilla
  #   roots have a serial number of 0);
  # - inside its validity period at the validation time (anchors included);
  # - a key Beryl verifies with (RSA of 2,048 to 8,192 bits, P-256, P-384,
  #   Ed25519) and, for every certificate below an anchor, a signature by
  #   its issuer in one of the algorithms listed in `SignatureAlgorithm`.
  #
  # Issuers (intermediates and anchors): basic constraints present,
  # critical and with cA set; keyCertSign when key usage is present; a
  # non-empty subject; path length constraints met, self-issued
  # intermediates not counted; well-formed name constraints, applied to
  # every certificate below them except self-issued intermediates.
  # Intermediates also need a subject key identifier and, when they carry
  # extended key usage, the purpose asked for. An anchor
  # needs no subject key identifier (Mozilla's TWCA Global Root CA has
  # none) and may not carry extended key usage; its authority key
  # identifier, when present, must hold only a key identifier, equal to
  # its subject key identifier when the anchor is self-issued.
  #
  # The leaf: not a CA, no keyCertSign, no name constraints, and extended
  # key usage either absent or non-critical,
  # without anyExtendedKeyUsage and with the purpose asked for. A server
  # leaf needs a subject alternative name (critical exactly when the
  # subject is empty). A common name is not matched against the reference
  # identity (RFC 9525 §6.1), but it must be well formed: an IP address in
  # canonical form, ASCII only, and an exact copy of a dNSName entry when
  # it holds an A-label or equals one apart from letter case (CA/Browser
  # Forum baseline requirements §7.1.4.3).
  class ChainVerification
    # The bounds on one verification, for chains from untrusted peers.
    struct Limits
      # Intermediates on one path (the plan's depth bound).
      getter largest_path_depth : Int32
      # Signatures checked while building paths, the bound on candidates tried.
      getter largest_signature_check_count : Int32
      # Elapsed time for one verification.
      getter largest_elapsed_time : Time::Span
      # Certificates presented: the leaf and the intermediates.
      getter largest_presented_certificate_count : Int32
      # Bytes presented: the leaf and the intermediates.
      getter largest_presented_bytesize : Int32
      # Name constraint comparisons over the whole verification.
      getter largest_name_constraint_comparison_count : Int64

      def initialize(
        *,
        @largest_path_depth : Int32 = 8,
        @largest_signature_check_count : Int32 = 100,
        @largest_elapsed_time : Time::Span = 50.milliseconds,
        @largest_presented_certificate_count : Int32 = 64,
        @largest_presented_bytesize : Int32 = 65_536,
        @largest_name_constraint_comparison_count : Int64 = 250_000_i64,
      )
      end
    end

    getter trust_store : TrustStore
    getter limits : Limits

    def initialize(@trust_store : TrustStore, *, @limits : Limits = Limits.new)
    end

    # Verifies *leaf* through *list_of_intermediates* to an anchor of the
    # trust store and returns the path, leaf first and anchor last. Raises
    # `VerificationFailed` naming the reason.
    #
    # - *identity*: the name the leaf must carry (checked when given).
    # - *purpose*: the extended key usage asked for.
    # - *time*: the validation time.
    # - *required_key_usage*: bits the leaf's key usage must have when it
    #   carries the extension (for TLS 1.3, `KeyUsage::DigitalSignature`).
    # - *list_of_revocation_lists*: CRLs to apply (see
    #   `CertificateRevocationList`).
    # - *largest_intermediate_count*: a caller's own bound on the
    #   intermediates of the path, self-issued ones not counted.
    def verify(
      leaf : Certificate,
      list_of_intermediates : Array(Certificate) = [] of Certificate,
      *,
      identity : ServiceIdentity? = nil,
      purpose : Purpose = Purpose::ServerAuthentication,
      time : Time = Time.utc,
      required_key_usage : KeyUsage = KeyUsage::None,
      list_of_revocation_lists : Array(CertificateRevocationList) = [] of CertificateRevocationList,
      largest_intermediate_count : Int32? = nil,
    ) : Array(Certificate)
      presented_count = 1 + list_of_intermediates.size
      presented_bytesize = leaf.encoded.size + list_of_intermediates.sum(&.encoded.size)
      if presented_count > @limits.largest_presented_certificate_count || presented_bytesize > @limits.largest_presented_bytesize
        raise VerificationFailed.new(FailureReason::TooManyCertificates,
          "#{presented_count} certificates of #{presented_bytesize} bytes were presented; the limits are #{@limits.largest_presented_certificate_count} and #{@limits.largest_presented_bytesize}")
      end

      if reason = ChainVerification.refused_signature_algorithm_violation(leaf)
        raise VerificationFailed.new(FailureReason::SignatureAlgorithmRefused, reason)
      end
      if reason = ChainVerification.leaf_profile_violation(leaf, purpose, required_key_usage)
        raise VerificationFailed.new(FailureReason::LeafProfileViolation, "the leaf #{leaf.subject}: #{reason}")
      end
      unless leaf.valid_at?(time)
        raise VerificationFailed.new(FailureReason::LeafExpiredOrNotYetValid, "the leaf #{leaf.subject} is not valid at #{time} (#{leaf.not_before} to #{leaf.not_after})")
      end
      if reason = ChainVerification.extended_key_usage_violation(leaf, purpose)
        raise VerificationFailed.new(FailureReason::UsageNotAllowed, "the leaf #{leaf.subject}: #{reason}")
      end
      if identity && !identity.matches?(leaf)
        raise VerificationFailed.new(FailureReason::NameMismatch, "no subject alternative name of the leaf matches #{identity}")
      end

      search = PathSearch.new(self, list_of_intermediates, purpose, time, list_of_revocation_lists, largest_intermediate_count)
      path = search.find([leaf])
      return path if path

      if search.revocation_failure?
        raise VerificationFailed.new(FailureReason::Revoked, search.last_failure || "revoked")
      end
      if refused_signature_failure = search.refused_signature_failure
        raise VerificationFailed.new(FailureReason::SignatureAlgorithmRefused, refused_signature_failure)
      end
      raise VerificationFailed.new(FailureReason::NoTrustedPath,
        "no path from #{leaf.subject} to a trust anchor passed every check#{search.last_failure.try { |failure| ": #{failure}" }}")
    rescue exhausted : NameConstraintCheck::BudgetExhausted | BudgetSpent
      raise VerificationFailed.new(FailureReason::BudgetExceeded, "path building stopped at its budget: #{exhausted.message || "name constraint comparisons"}")
    end

    # :nodoc:
    class BudgetSpent < Exception
    end

    # :nodoc:
    #
    # Names the hash when *certificate* is signed with SHA-1 or MD5, which
    # Beryl refuses by the algorithm identifier alone, before any signature
    # check. A trust anchor's own signature is never checked, so this
    # applies to leaves and intermediates.
    def self.refused_signature_algorithm_violation(certificate : Certificate) : String?
      hash_function_name = certificate.signature_algorithm.refused_hash_function_name
      return nil unless hash_function_name

      standard = hash_function_name == "MD5" ? "RFC 6151" : "RFC 9155"
      "the certificate for #{certificate.subject} is signed with #{hash_function_name}, which Beryl refuses (#{standard})"
    end

    # :nodoc:
    #
    # Checks shared by every certificate of a path.
    def self.common_profile_violation(certificate : Certificate) : String?
      return "version #{certificate.version}; certificates must be version 3" unless certificate.version == 3
      return "an unknown critical extension" if certificate.has_unknown_critical_extension?
      return "an empty issuer name" if certificate.issuer.empty?

      certificate.list_of_extensions.each do |extension|
        case extension.identifier
        when ObjectIdentifiers::AUTHORITY_KEY_IDENTIFIER, ObjectIdentifiers::SUBJECT_KEY_IDENTIFIER, ObjectIdentifiers::AUTHORITY_INFORMATION_ACCESS
          return "the #{extension.identifier} extension is critical; RFC 5280 requires it non-critical" if extension.is_critical
        when ObjectIdentifiers::POLICY_CONSTRAINTS
          return "policy constraints are not critical (RFC 5280 §4.2.1.11)" unless extension.is_critical
        end
      end
      if (count = certificate.authority_information_access_count) && count == 0
        return "an authority information access extension with no access description"
      end
      if (usages = certificate.list_of_extended_key_usages) && usages.empty?
        return "an extended key usage extension with no purpose"
      end
      if (names = certificate.list_of_subject_alternative_names) && names.empty?
        return "a subject alternative name extension with no name"
      end

      nil
    end

    # :nodoc:
    #
    # RFC 5280 §4.1.2.2: positive, at most 20 bytes. Not applied to trust
    # anchors, some of which (Starfield Root G2) have serial number zero.
    def self.serial_number_violation(certificate : Certificate) : String?
      serial = certificate.serial_number
      return "a negative serial number" if serial[0] & 0x80 != 0
      return "a serial number of zero" if serial.all?(&.zero?)
      magnitude_bytesize = serial[0] == 0 ? serial.size - 1 : serial.size
      return "a serial number longer than 20 bytes" if magnitude_bytesize > 20
      nil
    end

    # :nodoc:
    #
    # Checks on any issuer, intermediate or anchor.
    def self.issuer_profile_violation(certificate : Certificate) : String?
      if reason = common_profile_violation(certificate)
        return reason
      end
      constraints = certificate.basic_constraints
      return "no basic constraints; an issuer needs cA set" unless constraints
      return "basic constraints without cA" unless constraints.is_certificate_authority
      return "basic constraints not marked critical" unless certificate.extension(ObjectIdentifiers::BASIC_CONSTRAINTS).try(&.is_critical)
      if (usage = certificate.key_usage) && !usage.key_certificate_sign?
        return "a key usage without keyCertSign"
      end
      return "an empty subject name" if certificate.subject.empty?
      if name_constraints = certificate.name_constraints
        if reason = NameConstraintCheck.malformed_reason(name_constraints)
          return reason
        end
      end
      unless certificate.subject_public_key_info.verification_key
        return "a key Beryl does not verify with (#{certificate.subject_public_key_info.unusable_key_reason})"
      end
      nil
    end

    # :nodoc:
    def self.intermediate_profile_violation(certificate : Certificate, purpose : Purpose) : String?
      if reason = issuer_profile_violation(certificate)
        return reason
      end
      return "no subject key identifier" unless certificate.subject_key_identifier
      if reason = serial_number_violation(certificate)
        return reason
      end
      if usages = certificate.list_of_extended_key_usages
        unless usages.includes?(purpose.object_identifier) || usages.includes?(ObjectIdentifiers::ANY_EXTENDED_KEY_USAGE)
          return "an extended key usage without #{purpose}"
        end
      end
      nil
    end

    # :nodoc:
    def self.anchor_profile_violation(certificate : Certificate) : String?
      if reason = issuer_profile_violation(certificate)
        return reason
      end
      return "an extended key usage extension on a trust anchor (CA/Browser Forum §7.1.2.1.2)" if certificate.list_of_extended_key_usages
      if identifier = certificate.authority_key_identifier
        key_identifier = identifier.key_identifier
        return "an authority key identifier without a key identifier" unless key_identifier
        if identifier.has_authority_certificate_issuer || identifier.has_authority_certificate_serial_number
          return "an authority key identifier with an issuer or serial number (CA/Browser Forum §7.1.2.1.3)"
        end
        if certificate.self_issued? && key_identifier != certificate.subject_key_identifier
          return "an authority key identifier that differs from the subject key identifier"
        end
      end
      nil
    end

    # :nodoc:
    def self.leaf_profile_violation(certificate : Certificate, purpose : Purpose, required_key_usage : KeyUsage) : String?
      if reason = common_profile_violation(certificate)
        return reason
      end
      if reason = serial_number_violation(certificate)
        return reason
      end
      if usage = certificate.key_usage
        if usage.key_certificate_sign? != certificate.certificate_authority?
          return "key usage keyCertSign and basic constraints cA disagree (RFC 5280 §4.2.1.3, §4.2.1.9)"
        end
        return "a key usage without #{required_key_usage}" unless usage.includes?(required_key_usage)
      end
      return "name constraints on a leaf" if certificate.name_constraints
      unless certificate.subject_public_key_info.verification_key
        return "a key Beryl does not verify with (#{certificate.subject_public_key_info.unusable_key_reason})"
      end
      if purpose.server_authentication?
        san = certificate.extension(ObjectIdentifiers::SUBJECT_ALTERNATIVE_NAME)
        return "no subject alternative name" unless san
        if certificate.subject.empty?
          return "a subject alternative name not marked critical under an empty subject" unless san.is_critical
        elsif san.is_critical
          return "a critical subject alternative name under a non-empty subject"
        end
        if reason = common_name_violation(certificate)
          return reason
        end
      end
      nil
    end

    # The common name rules of the baseline requirements §7.1.4.3, in the
    # parts that agree with the rest of x509-limbo (whose BetterTLS cases
    # accept a common name that is not among the subject alternative names):
    # a common name written as an IP address must be in canonical form
    # (RFC 3986 §3.2.2 dotted decimal, RFC 5952 §4 for IPv6); a common name
    # must be ASCII (P-labels are never converted to Unicode); a common name
    # that holds an A-label (`xn--`), or that equals a dNSName entry apart
    # from letter case, must be a character-for-character copy of a dNSName
    # entry.
    private def self.common_name_violation(certificate : Certificate) : String?
      list_of_dns_names = certificate.list_of_dns_names
      certificate.subject.list_of_common_names.each do |common_name_bytes|
        common_name = String.new(common_name_bytes)
        next if list_of_dns_names.includes?(common_name)

        if looks_like_ip_address?(common_name)
          address = ServiceIdentity.parse_ip_address(common_name)
          unless address && ServiceIdentity.format_ip_address(address) == common_name
            return "the common name #{common_name.inspect} is an IP address not in canonical form"
          end
        elsif !common_name.ascii_only?
          return "the common name #{common_name.inspect} is not ASCII"
        elsif common_name.split('.').any?(&.downcase.starts_with?("xn--"))
          return "the common name #{common_name.inspect} holds an A-label that is not a copy of a dNSName entry"
        elsif list_of_dns_names.any?(&.compare(common_name, case_insensitive: true).zero?)
          return "the common name #{common_name.inspect} differs from its dNSName entry in letter case"
        end
      end
      nil
    end

    # An IPv6 literal (it holds a colon) or anything the C library's
    # inet_aton would read as IPv4: one to four parts of decimal, octal or
    # 0x-prefixed hexadecimal digits.
    private def self.looks_like_ip_address?(text : String) : Bool
      return true if text.includes?(':')

      list_of_parts = text.split('.')
      return false if list_of_parts.size > 4
      list_of_parts.all? do |part|
        is_hexadecimal = part.downcase.starts_with?("0x")
        digits = is_hexadecimal ? part[2..] : part
        !digits.empty? && (is_hexadecimal ? digits.each_char.all?(&.hex?) : digits.each_char.all?(&.ascii_number?))
      end
    end

    # :nodoc:
    def self.extended_key_usage_violation(certificate : Certificate, purpose : Purpose) : String?
      usages = certificate.list_of_extended_key_usages
      return nil unless usages

      return "extended key usage marked critical on a leaf (CA/Browser Forum §7.1.2.7.6)" if certificate.extension(ObjectIdentifiers::EXTENDED_KEY_USAGE).try(&.is_critical)
      return "anyExtendedKeyUsage on a leaf (CA/Browser Forum §7.1.2.7.10)" if usages.includes?(ObjectIdentifiers::ANY_EXTENDED_KEY_USAGE)
      return "an extended key usage without #{purpose}" unless usages.includes?(purpose.object_identifier)
      nil
    end

    # The depth-first search for one verification, with its budget and
    # caches.
    private class PathSearch
      getter last_failure : String? = nil
      getter? revocation_failure = false
      # Set when an intermediate was passed over for a SHA-1 or MD5
      # signature; a search that finds no path reports it.
      getter refused_signature_failure : String? = nil

      @signature_check_count = 0
      @started_at : Time::Instant
      @verdict_by_signature = Hash({Certificate, Bytes}, Bool).new
      @issuer_violation : Hash(Certificate, String?) = Hash(Certificate, String?).new
      @name_constraint_check : NameConstraintCheck
      @intermediates_by_subject : Hash(Bytes, Array(Certificate))

      def initialize(@verification : ChainVerification, list_of_intermediates : Array(Certificate), @purpose : Purpose,
                     @time : Time, @list_of_revocation_lists : Array(CertificateRevocationList), @largest_intermediate_count : Int32?)
        @started_at = Time.instant
        @name_constraint_check = NameConstraintCheck.new(@verification.limits.largest_name_constraint_comparison_count)
        @intermediates_by_subject = Hash(Bytes, Array(Certificate)).new
        list_of_intermediates.uniq.each do |intermediate|
          (@intermediates_by_subject[intermediate.subject.encoded] ||= [] of Certificate) << intermediate
        end
      end

      # Extends *path* (leaf first) to an anchor; returns the full path or
      # `nil`.
      def find(path : Array(Certificate)) : Array(Certificate)?
        check_time
        current = path.last
        ordered(@verification.trust_store.list_of_anchors_named(current.issuer), current).each do |anchor|
          if reason = issuer_violation(anchor, is_anchor: true)
            note("the anchor #{anchor.subject}: #{reason}")
            next
          end
          next unless signature_verifies?(current, anchor)

          full_path = path + [anchor]
          if reason = path_violation(full_path)
            note(reason)
            next
          end
          return full_path
        end

        return nil if path.size - 1 >= @verification.limits.largest_path_depth

        ordered(@intermediates_by_subject[current.issuer.encoded]? || [] of Certificate, current).each do |intermediate|
          if path.any? { |seen| seen == intermediate || (seen.subject == intermediate.subject && seen.subject_public_key_info.encoded == intermediate.subject_public_key_info.encoded) }
            next
          end
          if reason = issuer_violation(intermediate, is_anchor: false)
            note("the intermediate #{intermediate.subject}: #{reason}")
            next
          end
          if reason = ChainVerification.refused_signature_algorithm_violation(intermediate)
            note(reason)
            @refused_signature_failure = reason
            next
          end
          next unless signature_verifies?(current, intermediate)

          if found = find(path + [intermediate])
            return found
          end
        end
        nil
      end

      private def note(failure : String) : Nil
        @last_failure = failure
      end

      private def check_time : Nil
        elapsed = Time.instant - @started_at
        raise BudgetSpent.new("#{elapsed.total_milliseconds.round(1)} ms elapsed") if elapsed > @verification.limits.largest_elapsed_time
      end

      # Candidates whose subject key identifier equals the child's
      # authority key identifier first, those without either next, the
      # mismatched last.
      private def ordered(list_of_candidates : Array(Certificate), child : Certificate) : Array(Certificate)
        wanted = child.authority_key_identifier.try(&.key_identifier)
        return list_of_candidates unless wanted

        list_of_candidates.sort_by do |candidate|
          identifier = candidate.subject_key_identifier
          identifier.nil? ? 1 : (identifier == wanted ? 0 : 2)
        end
      end

      private def issuer_violation(certificate : Certificate, *, is_anchor : Bool) : String?
        @issuer_violation.fetch(certificate) do
          reason = is_anchor ? ChainVerification.anchor_profile_violation(certificate) : ChainVerification.intermediate_profile_violation(certificate, @purpose)
          reason ||= "not valid at #{@time} (#{certificate.not_before} to #{certificate.not_after})" unless certificate.valid_at?(@time)
          @issuer_violation[certificate] = reason
        end
      end

      private def signature_verifies?(child : Certificate, issuer : Certificate) : Bool
        key = issuer.subject_public_key_info.verification_key
        return false unless key

        @verdict_by_signature.fetch({child, issuer.subject_public_key_info.encoded}) do
          @signature_check_count += 1
          if @signature_check_count > @verification.limits.largest_signature_check_count
            raise BudgetSpent.new("#{@signature_check_count - 1} signatures checked")
          end
          check_time
          verdict = child.signed_by?(key)
          note("the signature of #{child.subject} does not verify under the key of #{issuer.subject}") unless verdict
          @verdict_by_signature[{child, issuer.subject_public_key_info.encoded}] = verdict
        end
      end

      # Checks that need the whole path: path length constraints, the
      # caller's intermediate bound, name constraints and revocation.
      private def path_violation(path : Array(Certificate)) : String?
        (1...path.size).each do |issuer_index|
          issuer = path[issuer_index]
          if limit = issuer.basic_constraints.try(&.path_length_constraint)
            below = (1...issuer_index).count { |index| !path[index].self_issued? }
            return "#{issuer.subject} allows #{limit} intermediates below it, the path has #{below}" if below > limit
          end
        end

        if largest = @largest_intermediate_count
          intermediate_count = (1...path.size - 1).count { |index| !path[index].self_issued? }
          return "the path has #{intermediate_count} intermediates; at most #{largest} were allowed" if intermediate_count > largest
        end

        (1...path.size).each do |issuer_index|
          constraints = path[issuer_index].name_constraints
          next unless constraints

          (0...issuer_index).each do |index|
            subject = path[index]
            next if index > 0 && subject.self_issued?
            if reason = @name_constraint_check.violation(constraints, subject)
              return "#{subject.subject}: #{reason} of #{path[issuer_index].subject}"
            end
          end
        end

        unless @list_of_revocation_lists.empty?
          (0...path.size - 1).each do |index|
            certificate = path[index]
            issuer = path[index + 1]
            @list_of_revocation_lists.each do |revocation_list|
              next unless revocation_list.issuer == certificate.issuer

              if reason = revocation_list.unusable_reason(issuer, @time)
                @revocation_failure = true
                return "a CRL from #{certificate.issuer} cannot be used: #{reason}"
              end
              if revocation_list.revokes?(certificate.serial_number)
                @revocation_failure = true
                return "#{certificate.subject} is revoked by a CRL from #{certificate.issuer}"
              end
            end
          end
        end
        nil
      end
    end
  end
end
