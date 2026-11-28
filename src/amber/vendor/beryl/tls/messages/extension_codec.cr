require "./message_reader"

module Amber::Beryl::TLS::Messages
  # Reads and writes the contents of each extension Beryl understands.
  # Every reader consumes its whole input or raises `decode_error`.
  module ExtensionCodec
    # A key share: the group and the encoded public key.
    record KeyShareEntry, group_value : UInt16, key_exchange : Bytes

    # A PSK identity: the ticket and its obfuscated age.
    record PskIdentity, identity : Bytes, obfuscated_ticket_age : UInt32

    # server_name (RFC 6066 §3): the host_name, or `nil` for an empty
    # extension (the server's acknowledgement). Only one host_name entry
    # may appear.
    def self.decode_server_name(contents : Bytes) : String?
      return nil if contents.empty?
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector16(1))
      reader.finish
      host_name = nil
      until list.at_end?
        name_type = list.read_u8
        name = list.read_vector16(1)
        next unless name_type == 0
        raise Error.new("two host_name entries", AlertDescription::IllegalParameter) if host_name
        unless name.all? { |byte| byte > 0x20 && byte < 0x7F }
          raise Error.new("a host_name with bytes outside printable ASCII", AlertDescription::DecodeError)
        end
        host_name = String.new(name)
      end
      host_name
    end

    def self.encode_server_name(host_name : String) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 do |list|
        list.write_u8(0)
        list.write_vector16(host_name.to_slice)
      end
      writer.to_slice
    end

    # A list of two-byte values in a two-byte vector: supported_groups,
    # signature_algorithms, signature_algorithms_cert.
    def self.decode_u16_list(contents : Bytes) : Array(UInt16)
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector16(2))
      reader.finish
      raise Error.new("an odd-length list", AlertDescription::DecodeError) if list.remaining.odd?
      Array(UInt16).new(list.remaining // 2) { list.read_u16 }
    end

    # certificate_authorities (RFC 9846 §4.2.4): a non-empty two-byte
    # vector of DER distinguished names, each non-empty. Returns the names.
    def self.decode_certificate_authorities(contents : Bytes) : Array(Bytes)
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector16(3))
      reader.finish
      list_of_names = [] of Bytes
      until list.at_end?
        list_of_names << list.read_vector16(1)
      end
      list_of_names
    end

    def self.encode_u16_list(list_of_values : Array(UInt16)) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 { |list| list_of_values.each { |value| list.write_u16(value) } }
      writer.to_slice
    end

    # supported_versions in a ClientHello: a one-byte vector of versions.
    def self.decode_client_supported_versions(contents : Bytes) : Array(UInt16)
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector8(2))
      reader.finish
      raise Error.new("an odd-length version list", AlertDescription::DecodeError) if list.remaining.odd?
      Array(UInt16).new(list.remaining // 2) { list.read_u16 }
    end

    def self.encode_client_supported_versions(list_of_versions : Array(UInt16)) : Bytes
      writer = MessageWriter.new
      writer.write_vector8 { |list| list_of_versions.each { |version| list.write_u16(version) } }
      writer.to_slice
    end

    # supported_versions in a ServerHello: the selected version.
    def self.decode_selected_version(contents : Bytes) : UInt16
      reader = MessageReader.new(contents)
      version = reader.read_u16
      reader.finish
      version
    end

    def self.encode_selected_version(version : UInt16) : Bytes
      Bytes[(version >> 8).to_u8, (version & 0xFF).to_u8]
    end

    # key_share in a ClientHello. Two shares for one group are refused
    # (§4.2.8).
    def self.decode_client_key_shares(contents : Bytes) : Array(KeyShareEntry)
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector16)
      reader.finish
      list_of_entries = [] of KeyShareEntry
      seen_group_values = Set(UInt16).new
      until list.at_end?
        group = list.read_u16
        key_exchange = list.read_vector16(1)
        unless seen_group_values.add?(group)
          raise Error.new("two key shares for group #{group}", AlertDescription::IllegalParameter)
        end
        list_of_entries << KeyShareEntry.new(group, key_exchange)
      end
      list_of_entries
    end

    def self.encode_client_key_shares(list_of_entries : Array(KeyShareEntry)) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 do |list|
        list_of_entries.each do |entry|
          list.write_u16(entry.group_value)
          list.write_vector16(entry.key_exchange)
        end
      end
      writer.to_slice
    end

    # key_share in a ServerHello: one entry.
    def self.decode_server_key_share(contents : Bytes) : KeyShareEntry
      reader = MessageReader.new(contents)
      group = reader.read_u16
      key_exchange = reader.read_vector16(1)
      reader.finish
      KeyShareEntry.new(group, key_exchange)
    end

    def self.encode_server_key_share(entry : KeyShareEntry) : Bytes
      writer = MessageWriter.new
      writer.write_u16(entry.group_value)
      writer.write_vector16(entry.key_exchange)
      writer.to_slice
    end

    # key_share in a HelloRetryRequest: the selected group.
    def self.decode_selected_group(contents : Bytes) : UInt16
      reader = MessageReader.new(contents)
      group = reader.read_u16
      reader.finish
      group
    end

    def self.encode_selected_group(group : UInt16) : Bytes
      Bytes[(group >> 8).to_u8, (group & 0xFF).to_u8]
    end

    # psk_key_exchange_modes.
    def self.decode_psk_modes(contents : Bytes) : Bytes
      reader = MessageReader.new(contents)
      modes = reader.read_vector8(1)
      reader.finish
      modes
    end

    def self.encode_psk_modes(modes : Bytes) : Bytes
      writer = MessageWriter.new
      writer.write_vector8(modes)
      writer.to_slice
    end

    # application_layer_protocol_negotiation (RFC 7301 §3.1): the names,
    # none empty.
    def self.decode_protocol_names(contents : Bytes) : Array(String)
      reader = MessageReader.new(contents)
      list = MessageReader.new(reader.read_vector16(2))
      reader.finish
      list_of_names = [] of String
      until list.at_end?
        list_of_names << String.new(list.read_vector8(1))
      end
      list_of_names
    end

    def self.encode_protocol_names(list_of_names : Array(String)) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 { |list| list_of_names.each { |name| list.write_vector8(name.to_slice) } }
      writer.to_slice
    end

    # cookie (§4.2.2).
    def self.decode_cookie(contents : Bytes) : Bytes
      reader = MessageReader.new(contents)
      cookie = reader.read_vector16(1)
      reader.finish
      cookie
    end

    def self.encode_cookie(cookie : Bytes) : Bytes
      writer = MessageWriter.new
      writer.write_vector16(cookie)
      writer.to_slice
    end

    # record_size_limit (RFC 8449 §4): a value below 64 is refused.
    def self.decode_record_size_limit(contents : Bytes) : Int32
      reader = MessageReader.new(contents)
      limit = reader.read_u16.to_i
      reader.finish
      raise Error.new("a record_size_limit of #{limit}", AlertDescription::IllegalParameter) if limit < 64
      limit
    end

    def self.encode_record_size_limit(limit : Int32) : Bytes
      Bytes[(limit >> 8).to_u8, (limit & 0xFF).to_u8]
    end

    # pre_shared_key in a ClientHello (§4.2.11): identities and binders,
    # as many of each.
    def self.decode_client_pre_shared_key(contents : Bytes) : {Array(PskIdentity), Array(Bytes)}
      reader = MessageReader.new(contents)
      identities = MessageReader.new(reader.read_vector16(7))
      binders = MessageReader.new(reader.read_vector16(33))
      reader.finish
      list_of_identities = [] of PskIdentity
      until identities.at_end?
        list_of_identities << PskIdentity.new(identities.read_vector16(1), identities.read_u32)
      end
      list_of_binders = [] of Bytes
      until binders.at_end?
        list_of_binders << binders.read_vector8(32)
      end
      unless list_of_identities.size == list_of_binders.size
        raise Error.new("#{list_of_identities.size} PSK identities and #{list_of_binders.size} binders", AlertDescription::IllegalParameter)
      end
      {list_of_identities, list_of_binders}
    end

    def self.encode_client_pre_shared_key(list_of_identities : Array(PskIdentity), list_of_binders : Array(Bytes)) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 do |identities|
        list_of_identities.each do |identity|
          identities.write_vector16(identity.identity)
          identities.write_u32(identity.obfuscated_ticket_age)
        end
      end
      writer.write_vector16 { |binders| list_of_binders.each { |binder| binders.write_vector8(binder) } }
      writer.to_slice
    end

    # pre_shared_key in a ServerHello: the selected identity.
    def self.decode_selected_identity(contents : Bytes) : UInt16
      reader = MessageReader.new(contents)
      index = reader.read_u16
      reader.finish
      index
    end

    def self.encode_selected_identity(index : Int) : Bytes
      Bytes[(index >> 8).to_u8, (index & 0xFF).to_u8]
    end

    # certificate_authorities (§4.2.4): DER distinguished names, each in a
    # two-byte vector, in a two-byte vector.
    def self.encode_certificate_authorities(list_of_names : Array(Bytes)) : Bytes
      writer = MessageWriter.new
      writer.write_vector16 { |list| list_of_names.each { |name| list.write_vector16(name) } }
      writer.to_slice
    end
  end
end
