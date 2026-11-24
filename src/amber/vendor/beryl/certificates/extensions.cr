require "./general_name"

module Amber::Beryl::Certificates
  # One certificate or CRL extension as encoded (RFC 5280 §4.1): its
  # identifier, whether it is critical, and the DER inside its OCTET STRING.
  record Extension,
    identifier : Encoding::DER::ObjectIdentifier,
    is_critical : Bool,
    value : Bytes,
    element : Encoding::DER::Element

  # Basic constraints (RFC 5280 §4.2.1.9).
  record BasicConstraints, is_certificate_authority : Bool, path_length_constraint : Int64?

  # Key usage bits (RFC 5280 §4.2.1.3), numbered as the RFC numbers them.
  @[Flags]
  enum KeyUsage : UInt16
    DigitalSignature   = 1 << 0
    ContentCommitment  = 1 << 1
    KeyEncipherment    = 1 << 2
    DataEncipherment   = 1 << 3
    KeyAgreement       = 1 << 4
    KeyCertificateSign = 1 << 5
    CrlSign            = 1 << 6
    EncipherOnly       = 1 << 7
    DecipherOnly       = 1 << 8
  end

  # Authority key identifier (RFC 5280 §4.2.1.1).
  record AuthorityKeyIdentifier, key_identifier : Bytes?, has_authority_certificate_issuer : Bool, has_authority_certificate_serial_number : Bool

  # Name constraints (RFC 5280 §4.2.1.10). A subtree whose `minimum` or
  # `maximum` field is present is noted in `has_subtree_with_bounds`, since
  # RFC 5280 forbids them and Beryl refuses such a constraint.
  record NameConstraints,
    list_of_permitted_subtrees : Array(GeneralName)?,
    list_of_excluded_subtrees : Array(GeneralName)?,
    has_subtree_with_bounds : Bool

  # Policy constraints (RFC 5280 §4.2.1.11).
  record PolicyConstraints, require_explicit_policy : Int64?, inhibit_policy_mapping : Int64?

  # :nodoc:
  #
  # Decoders for the contents of the extensions Beryl reads. Each takes a
  # reader over the extension's OCTET STRING contents and reads it to the
  # end; the caller turns any `Encoding::Error` into `MalformedCertificate`.
  module ExtensionDecoding
    alias DER = Encoding::DER

    def self.basic_constraints(reader : DER::Reader) : BasicConstraints
      reader.read_sequence do |sequence|
        # DER omits a DEFAULT FALSE; an explicit FALSE is accepted, as Go,
        # OpenSSL and BoringSSL accept it, because CAs have issued it.
        is_certificate_authority = sequence.next_is?(DER::BOOLEAN) ? sequence.read_boolean : false
        path_length = sequence.next_is?(DER::INTEGER) ? sequence.read_small_integer : nil
        if path_length && path_length < 0
          raise Encoding::MalformedEncoding.new("a negative path length constraint")
        end
        BasicConstraints.new(is_certificate_authority, path_length)
      end
    end

    def self.key_usage(reader : DER::Reader) : KeyUsage
      bit_string = reader.read_bit_string
      raise Encoding::MalformedEncoding.new("a key usage with more than 9 bits") if bit_string.bit_count > 16
      usage = KeyUsage::None
      9.times do |index|
        usage |= KeyUsage.new(1_u16 << index) if bit_string.bit_set?(index)
      end
      raise Encoding::MalformedEncoding.new("a key usage with no bit set (RFC 5280 §4.2.1.3)") if usage.none?
      usage
    end

    def self.extended_key_usage(reader : DER::Reader) : Array(DER::ObjectIdentifier)
      reader.read_sequence do |sequence|
        list_of_usages = [] of DER::ObjectIdentifier
        until sequence.at_end?
          list_of_usages << sequence.read_object_identifier
        end
        list_of_usages
      end
    end

    def self.subject_key_identifier(reader : DER::Reader) : Bytes
      reader.read_octet_string
    end

    def self.authority_key_identifier(reader : DER::Reader) : AuthorityKeyIdentifier
      reader.read_sequence do |sequence|
        key_identifier = sequence.read_optional_element(DER::Tag.context_specific(0, is_constructed: false)).try(&.content)
        issuer = sequence.read_optional_element(DER::Tag.context_specific(1, is_constructed: true))
        if issuer
          sequence.enter(issuer) do |names|
            until names.at_end?
              GeneralName.read(names)
            end
          end
        end
        serial = sequence.read_optional_element(DER::Tag.context_specific(2, is_constructed: false))
        DER.check_minimal_integer(serial) if serial
        AuthorityKeyIdentifier.new(key_identifier, !issuer.nil?, !serial.nil?)
      end
    end

    def self.subject_alternative_names(reader : DER::Reader) : Array(GeneralName)
      GeneralName.read_list(reader)
    end

    def self.name_constraints(reader : DER::Reader) : NameConstraints
      has_subtree_with_bounds = false
      permitted = nil
      excluded = nil
      reader.read_sequence do |sequence|
        {0_u32, 1_u32}.each do |number|
          element = sequence.read_optional_element(DER::Tag.context_specific(number, is_constructed: true))
          next unless element

          list_of_subtrees = sequence.enter(element) do |subtrees|
            list = [] of GeneralName
            until subtrees.at_end?
              subtrees.read_sequence do |subtree|
                list << GeneralName.read(subtree)
                unless subtree.at_end?
                  has_subtree_with_bounds = true
                  until subtree.at_end?
                    subtree.read_element
                  end
                end
              end
            end
            list
          end
          if number == 0
            permitted = list_of_subtrees
          else
            excluded = list_of_subtrees
          end
        end
      end
      NameConstraints.new(permitted, excluded, has_subtree_with_bounds)
    end

    def self.policy_constraints(reader : DER::Reader) : PolicyConstraints
      reader.read_sequence do |sequence|
        require_explicit = sequence.next_is?(DER::Tag.context_specific(0, is_constructed: false)) ? sequence.read_small_integer(DER::Tag.context_specific(0, is_constructed: false)) : nil
        inhibit_mapping = sequence.next_is?(DER::Tag.context_specific(1, is_constructed: false)) ? sequence.read_small_integer(DER::Tag.context_specific(1, is_constructed: false)) : nil
        PolicyConstraints.new(require_explicit, inhibit_mapping)
      end
    end

    # Certificate policies (RFC 5280 §4.2.1.4): read for structure only.
    # Returns the number of policies.
    def self.certificate_policies(reader : DER::Reader) : Int32
      reader.read_sequence do |sequence|
        count = 0
        until sequence.at_end?
          sequence.read_sequence do |policy|
            policy.read_object_identifier
            policy.read_element(DER::SEQUENCE) unless policy.at_end?
          end
          count += 1
        end
        count
      end
    end

    # CRL distribution points and freshest CRL (RFC 5280 §4.2.1.13 and
    # §4.2.1.15): read for structure, as OpenSSL reads them. Returns the
    # number of distribution points.
    def self.distribution_points(reader : DER::Reader) : Int32
      reader.read_sequence do |sequence|
        count = 0
        until sequence.at_end?
          sequence.read_sequence do |point|
            if name = point.read_optional_element(DER::Tag.context_specific(0, is_constructed: true))
              point.enter(name) do |choice|
                if full_name = choice.read_optional_element(DER::Tag.context_specific(0, is_constructed: true))
                  choice.enter(full_name) { |names| read_general_names(names) }
                else
                  relative_name = choice.read_element(DER::Tag.context_specific(1, is_constructed: true))
                  choice.enter(relative_name) do |set|
                    raise Encoding::MalformedEncoding.new("an empty nameRelativeToCRLIssuer", relative_name.offset) if set.at_end?
                    until set.at_end?
                      set.read_sequence do |pair|
                        pair.read_object_identifier
                        pair.read_element
                      end
                    end
                  end
                end
              end
            end
            if reasons = point.read_optional_element(DER::Tag.context_specific(1, is_constructed: false))
              DER.decode_bit_string(reasons)
            end
            if issuer = point.read_optional_element(DER::Tag.context_specific(2, is_constructed: true))
              point.enter(issuer) { |names| read_general_names(names) }
            end
          end
          count += 1
        end
        raise Encoding::MalformedEncoding.new("an empty list of distribution points") if count == 0
        count
      end
    end

    # Reads the GeneralName elements of an implicitly tagged GeneralNames
    # (SIZE (1..MAX)) up to the end of *reader*.
    private def self.read_general_names(reader : DER::Reader) : Nil
      raise Encoding::MalformedEncoding.new("an empty GeneralNames") if reader.at_end?
      until reader.at_end?
        GeneralName.read(reader)
      end
    end

    # Authority (or subject) information access (RFC 5280 §4.2.2.1):
    # read for structure. Returns the number of access descriptions.
    def self.information_access(reader : DER::Reader) : Int32
      reader.read_sequence do |sequence|
        count = 0
        until sequence.at_end?
          sequence.read_sequence do |description|
            description.read_object_identifier
            GeneralName.read(description)
          end
          count += 1
        end
        count
      end
    end
  end
end
