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

    # Common format patterns
    PATTERNS = {
      FormatType::Email    => /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}\z/,
      FormatType::URL      => /\A(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?\z/,
      FormatType::UUID     => /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/,
      FormatType::IPv4     => /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/,
      FormatType::IPv6     => /\A(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\z/,
      FormatType::Hostname => /\A([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*\z/,
      FormatType::Phone    => /\A\+?[1-9]\d{5,14}\z/, # E.164 format - minimum 6 digits total
    }

    def initialize(@field_name : String, @format : FormatType, @pattern : Regex? = nil)
      if @format == FormatType::Custom && @pattern.nil?
        raise ArgumentError.new("Custom format requires a pattern")
      end
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
              when FormatType::Custom
                @pattern.not_nil!.matches?(string_value)
              else
                pattern = PATTERNS[@format]?
                pattern ? pattern.matches?(string_value) : true
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
      return false unless /\A([01]?[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\z/.matches?(value)

      # Then validate it can be parsed as a time
      Time.parse(value, "%H:%M:%S", Time::Location::UTC)
      true
    rescue
      false
    end
  end
end
