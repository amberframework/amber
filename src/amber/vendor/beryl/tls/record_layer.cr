require "./record_protection"
require "./limits"

module Amber::Beryl::TLS
  # The record layer over an IO (RFC 9846 §5): writes and reads records,
  # protects them once keys are installed, reassembles handshake messages
  # and applies the plan's limits.
  #
  # It does not decide what a message means; the handshake state machines
  # and `Socket` do. What it refuses on its own, with the alert RFC 9846
  # names: records over the size limits (`record_overflow`), records that
  # fail authentication (`bad_record_mac`), plaintext application data or
  # a protected record with an outer type other than application_data
  # (`unexpected_message`), zero-length handshake or alert fragments, a
  # handshake message interleaved with another content type, an alert that
  # is not two bytes (`decode_error`), and the floods the limits bound.
  class RecordLayer
    # The largest plaintext fragment (§5.1).
    LARGEST_FRAGMENT_BYTESIZE = 16_384
    # A handshake message header: type and a 24-bit length.
    HANDSHAKE_HEADER_BYTESIZE = 4

    # Keys for reading, or `nil` before the ServerHello.
    property read_protection : RecordProtection? = nil
    # Keys for writing, or `nil` before the ServerHello.
    property write_protection : RecordProtection? = nil
    # The most content bytes per record written (the peer's
    # record_size_limit less one, RFC 8449 §4).
    property largest_outgoing_fragment_bytesize : Int32 = LARGEST_FRAGMENT_BYTESIZE
    # The largest inner plaintext (content, type and padding) a protected
    # record may carry: this end's record_size_limit once both ends sent
    # one (RFC 8449 §4), 2^14 + 1 bytes until then.
    property largest_incoming_inner_plaintext_bytesize : Int32 = RecordProtection::LARGEST_INNER_PLAINTEXT_BYTESIZE
    # Bytes of records that fail to open which a server still skips, while
    # it refuses the 0-RTT data a client offered (RFC 9846 §4.2.10).
    property early_data_skip_budget : Int32 = 0
    # Whether plaintext application_data records are skipped (within the
    # same budget): a client that offered 0-RTT and got a
    # HelloRetryRequest may still send them (§4.2.10).
    property? is_skipping_plaintext_early_data : Bool = false
    # Whether one compatibility change_cipher_spec is still accepted
    # (RFC 9846 §5, Appendix D.4). A server turns it off until the first
    # ClientHello is read; both ends turn it off once the handshake ends.
    property? is_change_cipher_spec_allowed : Bool = true
    # Whether a plaintext alert is read while protection is installed: a
    # server sets it while it waits for the client's flight, since a
    # client that refuses the ServerHello has no keys to protect its alert
    # with.
    property? is_accepting_plaintext_alerts : Bool = false
    @is_reading_handshake = false
    # Whether the peer sent close_notify.
    getter? peer_closed : Bool = false
    # Whether a close_notify was written.
    getter? closed_for_writing : Bool = false

    @consecutive_empty_record_count = 0
    @consecutive_warning_alert_count = 0
    @handshake_buffer = Bytes.empty
    # Spare room the handshake buffer grows into, doubling, so a message
    # sent in many small records costs linear time to reassemble.
    @handshake_storage = Bytes.empty
    @record_header = Bytes.new(RecordProtection::HEADER_BYTESIZE)

    def initialize(@io : IO, @limits : Limits = Limits.new)
    end

    # Writes *message* (a whole handshake message) in as many handshake
    # records as it takes. The first ClientHello goes out with the legacy
    # record version 0x0301 (§5.1).
    def write_handshake(message : Bytes, *, legacy_record_version : UInt16 = ProtocolVersion::TLS_1_2) : Nil
      write_content(ContentType::Handshake, message, legacy_record_version)
    end

    # Writes the one-byte compatibility change_cipher_spec record
    # (Appendix D.4), always in plaintext.
    def write_change_cipher_spec : Nil
      @io.write(Bytes[ContentType::ChangeCipherSpec.value, 0x03, 0x03, 0x00, 0x01, 0x01])
    end

    # Writes *content* as application data records.
    def write_application_data(content : Bytes) : Nil
      raise ConnectionClosed.new("the connection was closed for writing", AlertDescription::CloseNotify) if @closed_for_writing
      write_content(ContentType::ApplicationData, content, ProtocolVersion::TLS_1_2)
    end

    # Writes an alert. Errors from the IO are swallowed: an alert is the
    # last thing sent on a failing connection.
    def write_alert(level : AlertLevel, description : AlertDescription) : Nil
      return if @closed_for_writing
      @closed_for_writing = true if description.close_notify? || level.fatal?
      write_content(ContentType::Alert, Bytes[level.value, description.value], ProtocolVersion::TLS_1_2)
      @io.flush
    rescue IO::Error
    end

    # Flushes the IO.
    def flush : Nil
      @io.flush
    end

    # Returns whether no part of a handshake message is waiting. A key
    # change must not split a message (§5.1).
    def handshake_buffer_empty? : Bool
      @handshake_buffer.empty?
    end

    # Reads the next whole handshake message, header included. Raises when
    # anything but handshake records arrives, or the peer closes.
    def read_handshake_message : Bytes
      @is_reading_handshake = true
      loop do
        if message = take_buffered_handshake_message
          return message
        end
        content_type, content = read_content_record || raise Error.new("the peer closed the connection during the handshake", AlertDescription::UnexpectedMessage)
        unless content_type.handshake?
          raise Error.new("#{content_type} arrived during the handshake", AlertDescription::UnexpectedMessage)
        end
        append_handshake(content)
      end
    ensure
      @is_reading_handshake = false
    end

    # Reads the next record after the handshake. Returns application data
    # as `{ApplicationData, bytes}`, a whole post-handshake message as
    # `{Handshake, message}`, or `nil` once the peer sent close_notify.
    def read_after_handshake : {ContentType, Bytes}?
      loop do
        if message = take_buffered_handshake_message
          return {ContentType::Handshake, message}
        end
        record = read_content_record
        return nil unless record
        content_type, content = record
        if content_type.handshake?
          append_handshake(content)
        else
          unless handshake_buffer_empty?
            raise Error.new("application data inside a handshake message", AlertDescription::UnexpectedMessage)
          end
          return record
        end
      end
    end

    private def write_content(content_type : ContentType, content : Bytes, legacy_record_version : UInt16) : Nil
      fragment_limit = content_type.application_data? ? @largest_outgoing_fragment_bytesize : Math.min(@largest_outgoing_fragment_bytesize, LARGEST_FRAGMENT_BYTESIZE)
      offset = 0
      loop do
        fragment = content[offset, Math.min(fragment_limit, content.size - offset)]
        if protection = @write_protection
          @io.write(protection.seal(content_type, fragment))
        else
          header = Bytes[content_type.value, (legacy_record_version >> 8).to_u8, (legacy_record_version & 0xFF).to_u8,
            (fragment.size >> 8).to_u8, (fragment.size & 0xFF).to_u8]
          @io.write(header)
          @io.write(fragment)
        end
        offset += fragment.size
        break if offset >= content.size
      end
    end

    # Reads records until one carries handshake or application data.
    # Alerts, compatibility change_cipher_spec records and skipped 0-RTT
    # records are dealt with here. Returns `nil` at close_notify.
    private def read_content_record : {ContentType, Bytes}?
      return nil if @peer_closed
      loop do
        @io.read_fully(@record_header)
        outer_type = ContentType.new(@record_header[0])
        # An unknown record type is refused from its header, before its
        # length is trusted (§5); an SSL 2.0 ClientHello ends here too.
        unless ContentType::ChangeCipherSpec.value <= outer_type.value <= ContentType::ApplicationData.value
          raise Error.new("a record of type #{outer_type.value}", AlertDescription::UnexpectedMessage)
        end
        length = (@record_header[3].to_i << 8) | @record_header[4].to_i
        if length > RecordProtection::LARGEST_CIPHERTEXT_BYTESIZE
          raise Error.new("a record of #{length} bytes", AlertDescription::RecordOverflow)
        end
        fragment = Bytes.new(length)
        @io.read_fully(fragment)

        if outer_type.change_cipher_spec?
          unless @is_change_cipher_spec_allowed && length == 1 && fragment[0] == 1
            raise Error.new("an unexpected change_cipher_spec record", AlertDescription::UnexpectedMessage)
          end
          # A record boundary inside a handshake message is no place for it.
          unless handshake_buffer_empty?
            raise Error.new("a change_cipher_spec record inside a handshake message", AlertDescription::UnexpectedMessage)
          end
          @is_change_cipher_spec_allowed = false
          next
        end

        content_type, content = if protection = @read_protection
                                  if outer_type.alert? && @is_accepting_plaintext_alerts && length == 2
                                    return nil if read_alert(fragment, is_authenticated: false)
                                    next
                                  end
                                  unless outer_type.application_data?
                                    raise Error.new("a protected record of outer type #{outer_type}", AlertDescription::UnexpectedMessage)
                                  end
                                  # Checked before opening, so an oversized record costs no decryption.
                                  if length - protection.tag_bytesize > @largest_incoming_inner_plaintext_bytesize
                                    raise Error.new("a protected record over the record_size_limit of #{@largest_incoming_inner_plaintext_bytesize}", AlertDescription::RecordOverflow)
                                  end
                                  opened = protection.open(@record_header, fragment)
                                  unless opened
                                    next if skip_refused_early_data?(length)
                                    raise Error.new("a record failed authentication", AlertDescription::BadRecordMac)
                                  end
                                  @early_data_skip_budget = 0
                                  if opened[1].size > LARGEST_FRAGMENT_BYTESIZE
                                    raise Error.new("a record of #{opened[1].size} bytes of plaintext", AlertDescription::RecordOverflow)
                                  end
                                  opened
                                else
                                  if length > LARGEST_FRAGMENT_BYTESIZE
                                    raise Error.new("a plaintext record of #{length} bytes", AlertDescription::RecordOverflow)
                                  end
                                  if outer_type.application_data?
                                    next if @is_skipping_plaintext_early_data && skip_refused_early_data?(length)
                                    raise Error.new("application data before the handshake keys", AlertDescription::UnexpectedMessage)
                                  end
                                  {outer_type, fragment}
                                end

        case content_type
        when ContentType::Alert
          return nil if read_alert(content)
        when ContentType::Handshake
          raise Error.new("a zero-length handshake fragment", AlertDescription::UnexpectedMessage) if content.empty?
          @consecutive_warning_alert_count = 0
          return {content_type, content}
        when ContentType::ApplicationData
          @consecutive_warning_alert_count = 0
          # Application data of any length has no place in the handshake.
          return {content_type, content} if @is_reading_handshake
          if content.empty?
            @consecutive_empty_record_count += 1
            if @consecutive_empty_record_count > @limits.largest_consecutive_empty_record_count
              raise Error.new("more than #{@limits.largest_consecutive_empty_record_count} empty records in a row", AlertDescription::UnexpectedMessage)
            end
            next
          end
          @consecutive_empty_record_count = 0
          return {content_type, content}
        else
          raise Error.new("a record of content type #{content_type.value}", AlertDescription::UnexpectedMessage)
        end
      end
    end

    private def skip_refused_early_data?(length : Int32) : Bool
      return false if @early_data_skip_budget <= 0 || length > @early_data_skip_budget
      @early_data_skip_budget -= length
      true
    end

    # Handles an alert; returns true for close_notify, raises for every
    # other alert TLS 1.3 treats as fatal. An alert read in plaintext while
    # keys are installed (*is_authenticated* false) is reported as an
    # `UnauthenticatedAlert`, since anyone on the path could have sent it.
    private def read_alert(content : Bytes, *, is_authenticated : Bool = true) : Bool
      raise Error.new("an empty alert record", AlertDescription::UnexpectedMessage) if content.empty?
      raise Error.new("an alert of #{content.size} bytes", AlertDescription::DecodeError) unless content.size == 2
      unless handshake_buffer_empty?
        raise Error.new("an alert inside a handshake message", AlertDescription::UnexpectedMessage)
      end
      level = content[0]
      description = AlertDescription.new(content[1])
      unless is_authenticated
        raise UnauthenticatedAlert.new("an unauthenticated plaintext alert #{description}, which may not come from the peer", description)
      end
      if description.close_notify?
        @peer_closed = true
        return true
      end
      # user_canceled is the one warning TLS 1.3 lets through (§6.1); a
      # run of them is bounded.
      if description.user_canceled? && level == AlertLevel::Warning.value
        @consecutive_warning_alert_count += 1
        if @consecutive_warning_alert_count > @limits.largest_consecutive_warning_alert_count
          raise Error.new("more than #{@limits.largest_consecutive_warning_alert_count} warning alerts in a row", AlertDescription::UnexpectedMessage)
        end
        return false
      end
      raise PeerAlert.new("the peer sent the alert #{description}", description)
    end

    private def append_handshake(content : Bytes) : Nil
      if @handshake_buffer.empty?
        @handshake_buffer = content
      else
        size = @handshake_buffer.size
        needed = size + content.size
        is_in_storage = !@handshake_storage.empty? && @handshake_buffer.to_unsafe == @handshake_storage.to_unsafe
        unless is_in_storage && @handshake_storage.size >= needed
          storage = Bytes.new(Math.max(needed, size * 2))
          @handshake_buffer.copy_to(storage)
          @handshake_storage = storage
        end
        content.copy_to(@handshake_storage + size)
        @handshake_buffer = @handshake_storage[0, needed]
      end
      # Refuse as soon as a declared length is over the limit, before the
      # rest of the message is read.
      if @handshake_buffer.size >= HANDSHAKE_HEADER_BYTESIZE
        declared = declared_length(@handshake_buffer)
        if declared > @limits.largest_handshake_message_bytesize
          raise Error.new("a handshake message of #{declared} bytes", AlertDescription::IllegalParameter)
        end
      end
    end

    private def take_buffered_handshake_message : Bytes?
      return nil if @handshake_buffer.size < HANDSHAKE_HEADER_BYTESIZE
      total = HANDSHAKE_HEADER_BYTESIZE + declared_length(@handshake_buffer)
      return nil if @handshake_buffer.size < total
      message = @handshake_buffer[0, total]
      @handshake_buffer = @handshake_buffer[total..]
      if @handshake_buffer.size >= HANDSHAKE_HEADER_BYTESIZE && declared_length(@handshake_buffer) > @limits.largest_handshake_message_bytesize
        raise Error.new("a handshake message of #{declared_length(@handshake_buffer)} bytes", AlertDescription::IllegalParameter)
      end
      message
    end

    private def declared_length(buffer : Bytes) : Int32
      (buffer[1].to_i << 16) | (buffer[2].to_i << 8) | buffer[3].to_i
    end
  end
end
