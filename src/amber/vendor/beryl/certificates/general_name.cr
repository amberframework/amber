require "./distinguished_name"

module Amber::Beryl::Certificates
  # One GeneralName (RFC 5280 §4.2.1.6), as subject alternative names and
  # name constraints carry them.
  struct GeneralName
    # The CHOICE alternatives, numbered by their context-specific tags.
    enum Kind : UInt8
      OtherName                 = 0
      ElectronicMailAddress     = 1
      DomainName                = 2
      X400Address               = 3
      DirectoryName             = 4
      ElectronicDataInterchange = 5
      UniformResourceIdentifier = 6
      InternetProtocolAddress   = 7
      RegisteredIdentifier      = 8
    end

    getter kind : Kind
    # The contents: the IA5String bytes for the three text kinds, the
    # address bytes for an IP address (4 or 16 bytes in a subject
    # alternative name, 8 or 32 with the mask in a name constraint), the
    # encoded Name for a directory name, the raw contents otherwise.
    getter value : Bytes
    getter directory_name : DistinguishedName?

    def initialize(@kind : Kind, @value : Bytes, @directory_name : DistinguishedName? = nil)
    end

    # Reads one GeneralName. IA5String values must be ASCII (X.680 §41).
    def self.read(reader : Encoding::DER::Reader) : GeneralName
      element = reader.read_element
      tag = element.tag
      unless tag.tag_class.context_specific? && tag.number <= 8
        raise Encoding::MalformedEncoding.new("a GeneralName has tag #{tag}", element.offset)
      end
      kind = Kind.new(tag.number.to_u8)
      expected_constructed = kind.other_name? || kind.x400_address? || kind.directory_name? || kind.electronic_data_interchange?
      unless tag.is_constructed == expected_constructed
        raise Encoding::MalformedEncoding.new("a GeneralName #{kind} with the wrong constructed bit", element.offset)
      end

      case kind
      when .electronic_mail_address?, .domain_name?, .uniform_resource_identifier?
        unless element.content.all? { |byte| byte < 0x80 }
          raise Encoding::MalformedEncoding.new("an IA5String with a byte outside ASCII", element.offset)
        end
        GeneralName.new(kind, element.content)
      when .directory_name?
        name = reader.enter(element) { |inner| DistinguishedName.read(inner) }
        GeneralName.new(kind, name.encoded, name)
      when .registered_identifier?
        Encoding::DER.check_object_identifier(element)
        GeneralName.new(kind, element.content)
      when .other_name?
        reader.enter(element) do |inner|
          inner.read_object_identifier
          value = inner.read_element(Encoding::DER::Tag.context_specific(0, is_constructed: true))
          inner.enter(value) { |explicit| explicit.check_universal_contents(explicit.read_element) }
        end
        GeneralName.new(kind, element.content)
      when .electronic_data_interchange?
        # EDIPartyName ::= SEQUENCE { nameAssigner [0] DirectoryString
        # OPTIONAL, partyName [1] DirectoryString }, each explicitly tagged.
        reader.enter(element) do |inner|
          if assigner = inner.read_optional_element(Encoding::DER::Tag.context_specific(0, is_constructed: true))
            read_directory_string(inner, assigner)
          end
          read_directory_string(inner, inner.read_element(Encoding::DER::Tag.context_specific(1, is_constructed: true)))
        end
        GeneralName.new(kind, element.content)
      when .internet_protocol_address?
        GeneralName.new(kind, element.content)
      else
        # An X.400 address: kept as it is, its contents checked as DER.
        reader.enter(element) do |inner|
          until inner.at_end?
            inner.check_universal_contents(inner.read_element)
          end
        end
        GeneralName.new(kind, element.content)
      end
    end

    # Reads the one DirectoryString inside the explicit tag *element*.
    private def self.read_directory_string(reader : Encoding::DER::Reader, element : Encoding::DER::Element) : Nil
      reader.enter(element) do |explicit|
        value = explicit.read_element
        unless value.tag.tag_class.universal? && {12_u32, 19_u32, 20_u32, 28_u32, 30_u32}.includes?(value.tag.number)
          raise Encoding::MalformedEncoding.new("a DirectoryString with tag #{value.tag}", value.offset)
        end
        if reason = DistinguishedName.malformed_value_reason(value)
          raise Encoding::MalformedEncoding.new(reason, value.offset)
        end
      end
    end

    # Reads a SEQUENCE OF GeneralName (GeneralNames).
    def self.read_list(reader : Encoding::DER::Reader) : Array(GeneralName)
      reader.read_sequence do |sequence|
        list_of_names = [] of GeneralName
        until sequence.at_end?
          list_of_names << read(sequence)
        end
        list_of_names
      end
    end

    # The value as text, for the three IA5String kinds.
    def text : String
      String.new(@value)
    end
  end
end
