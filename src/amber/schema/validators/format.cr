# Format validation for strings (email, URL, UUID, etc.)
module Amber::Schema::Validator
  class Format < Base
    # Supported formats
    enum FormatType
      Email
      URL
      UUID
      Date
      DateTime
      Time
      IPv4
      IPv6
      Hostname
      Phone
      Custom
    end

    @custom_format_matches : Proc(String, Bool)?

    def initialize(@field_name : String, @format : FormatType, pattern : Nil = nil)
      if @format == FormatType::Custom
        raise ArgumentError.new("Custom format requires a pattern")
      end
    end

    # Compiles only in an app that passes a `Regex`, so other apps link no regex engine.
    def initialize(@field_name : String, @format : FormatType, pattern : Regex)
      @custom_format_matches = ->(text : String) { pattern.matches?(text) }
    end

    def validate(context : Context) : Nil
      return unless value = context.field_value(@field_name)
      return unless string_value = value.as_s?

      valid = case @format
              when FormatType::Date
                validate_date(string_value)
              when FormatType::DateTime
                validate_datetime(string_value)
              when FormatType::Time
                validate_time(string_value)
              when FormatType::Email
                Support::TextFormats.email?(string_value)
              when FormatType::URL
                Support::TextFormats.web_address?(string_value)
              when FormatType::UUID
                Support::TextFormats.uuid?(string_value)
              when FormatType::IPv4
                Support::TextFormats.ipv4?(string_value)
              when FormatType::IPv6
                Support::TextFormats.ipv6?(string_value)
              when FormatType::Hostname
                Support::TextFormats.hostname?(string_value)
              when FormatType::Phone
                Support::TextFormats.phone?(string_value)
              else
                custom_format_matches = @custom_format_matches
                custom_format_matches ? custom_format_matches.call(string_value) : true
              end

      unless valid
        context.add_error(InvalidFormatError.new(@field_name, @format.to_s.downcase, string_value))
      end
    end

    private def validate_date(value : String) : Bool
      Time.parse(value, "%Y-%m-%d", Time::Location::UTC)
      true
    rescue
      false
    end

    private def validate_datetime(value : String) : Bool
      Time.parse_iso8601(value)
      true
    rescue
      false
    end

    private def validate_time(value : String) : Bool
      # First check if it matches the strict 24-hour format pattern
      return false unless Support::TextFormats.time_of_day?(value)

      # Then validate it can be parsed as a time
      Time.parse(value, "%H:%M:%S", Time::Location::UTC)
      true
    rescue
      false
    end
  end
end
