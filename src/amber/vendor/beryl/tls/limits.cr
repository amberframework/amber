module Amber::Beryl::TLS
  # The bounds a connection puts on what its peer sends (plan §4, "Limits
  # on untrusted input"). The defaults are the plan's; an application may
  # tighten them through `Context::Client#limits=` or
  # `Context::Server#limits=`.
  struct Limits
    # The largest handshake message read, header excluded.
    getter largest_handshake_message_bytesize : Int32
    # The largest Certificate message's certificate list.
    getter largest_certificate_chain_bytesize : Int32
    # The most certificates in one Certificate message.
    getter largest_certificate_count : Int32
    # The most records in a row that carry no content.
    getter largest_consecutive_empty_record_count : Int32
    # The most warning alerts in a row (closes the "SSL Death Alert" class,
    # CVE-2016-8610).
    getter largest_consecutive_warning_alert_count : Int32
    # The most KeyUpdate messages read in one minute.
    getter largest_key_update_count_per_minute : Int32
    # The most bytes of refused 0-RTT records a server skips (RFC 9846
    # §4.2.10).
    getter largest_skipped_early_data_bytesize : Int32
    # How long a handshake may take before the socket is closed.
    getter handshake_timeout : Time::Span
    # The record_size_limit this end announces (RFC 8449): the largest
    # protected record's inner plaintext, content type and padding
    # included, that it accepts from its peer once both ends sent the
    # extension. Between 64 and 16,385; a smaller value lowers the memory
    # a connection needs for each record it reads.
    getter record_size_limit : Int32
    # How many records are sealed under one key before the connection
    # moves to the next with a KeyUpdate. The default stays well under the
    # AES-GCM confidentiality limit of RFC 9846 §5.5 (2^24.5 full-size
    # records) and applies to every suite.
    getter largest_record_count_per_key : UInt64

    def initialize(
      *,
      @largest_handshake_message_bytesize : Int32 = 65_536,
      @largest_certificate_chain_bytesize : Int32 = 65_536,
      @largest_certificate_count : Int32 = 10,
      @largest_consecutive_empty_record_count : Int32 = 32,
      @largest_consecutive_warning_alert_count : Int32 = 1,
      @largest_key_update_count_per_minute : Int32 = 32,
      @largest_skipped_early_data_bytesize : Int32 = 16_384,
      @handshake_timeout : Time::Span = 10.seconds,
      @record_size_limit : Int32 = 16_385,
      @largest_record_count_per_key : UInt64 = 16_777_216_u64,
    )
      unless 64 <= @record_size_limit <= RecordProtection::LARGEST_INNER_PLAINTEXT_BYTESIZE
        raise ArgumentError.new("a record_size_limit of #{@record_size_limit}; RFC 8449 allows 64 to 16,385 in TLS 1.3")
      end
      raise ArgumentError.new("a key must seal at least one record") if @largest_record_count_per_key == 0
    end
  end
end
