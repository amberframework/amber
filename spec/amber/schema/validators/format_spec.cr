require "../../../spec_helper"

module Amber::Schema
  class TestSchema < Definition
  end
end

module Amber::Schema::Validator
  describe Format do
    describe "#validate" do
      describe "Email format" do
        it "passes for valid email addresses" do
          validator = Format.new("email", Format::FormatType::Email)
          valid_emails = [
            "test@example.com",
            "user.name@example.com",
            "user+tag@example.co.uk",
            "test123@test-domain.com",
            "a@b.co",
          ]

          valid_emails.each do |email|
            data = {"email" => JSON::Any.new(email)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{email} to be valid"
          end
        end

        it "fails for invalid email addresses" do
          validator = Format.new("email", Format::FormatType::Email)
          invalid_emails = [
            "invalid",
            "@example.com",
            "user@",
            "user@.com",
            "user@example",
            "user space@example.com",
            "user@example..com",
          ]

          invalid_emails.each do |email|
            data = {"email" => JSON::Any.new(email)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{email} to be invalid"
            error = result.errors.first
            error.should be_a(InvalidFormatError)
            error.field.should eq("email")
            error.details.not_nil!["format"].as_s.should eq("email")
            error.details.not_nil!["value"].as_s.should eq(email)
          end
        end
      end

      describe "URL format" do
        it "passes for valid URLs" do
          validator = Format.new("url", Format::FormatType::URL)
          valid_urls = [
            "http://example.com",
            "https://example.com",
            "https://subdomain.example.com",
            "https://example.com/path",
            "https://example.com/path/to/resource",
            "example.com",
            "subdomain.example.co.uk",
          ]

          valid_urls.each do |url|
            data = {"url" => JSON::Any.new(url)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{url} to be valid"
          end
        end

        it "fails for invalid URLs" do
          validator = Format.new("url", Format::FormatType::URL)
          invalid_urls = [
            "not a url",
            "ftp://example.com", # Only http/https supported
            "http://",
            "://example.com",
            "http:/example.com",
            "http://example",
            "http://example.",
          ]

          invalid_urls.each do |url|
            data = {"url" => JSON::Any.new(url)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{url} to be invalid"
          end
        end
      end

      describe "UUID format" do
        it "passes for valid UUIDs" do
          validator = Format.new("uuid", Format::FormatType::UUID)
          valid_uuids = [
            "550e8400-e29b-41d4-a716-446655440000",
            "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
            "6ba7b811-9dad-11d1-80b4-00c04fd430c8",
            "6ba7b812-9dad-11d1-80b4-00c04fd430c8",
            "6ba7b814-9dad-11d1-80b4-00c04fd430c8",
          ]

          valid_uuids.each do |uuid|
            data = {"uuid" => JSON::Any.new(uuid)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{uuid} to be valid"
          end
        end

        it "fails for invalid UUIDs" do
          validator = Format.new("uuid", Format::FormatType::UUID)
          invalid_uuids = [
            "not-a-uuid",
            "550e8400-e29b-41d4-a716",
            "550e8400-e29b-41d4-a716-446655440000-extra",
            "550e8400e29b41d4a716446655440000",     # Missing hyphens
            "g50e8400-e29b-41d4-a716-446655440000", # Invalid character
          ]

          invalid_uuids.each do |uuid|
            data = {"uuid" => JSON::Any.new(uuid)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{uuid} to be invalid"
          end
        end
      end

      describe "Date format" do
        it "passes for valid dates" do
          validator = Format.new("date", Format::FormatType::Date)
          valid_dates = [
            "2023-12-25",
            "2000-01-01",
            "2023-02-28",
            "2024-02-29", # Leap year
          ]

          valid_dates.each do |date|
            data = {"date" => JSON::Any.new(date)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{date} to be valid"
          end
        end

        it "fails for invalid dates" do
          validator = Format.new("date", Format::FormatType::Date)
          invalid_dates = [
            "2023-13-01", # Invalid month
            "2023-12-32", # Invalid day
            "2023-02-29", # Not a leap year
            "12-25-2023", # Wrong format
            "2023/12/25", # Wrong separator
            "not a date",
            "2023-12", # Missing day
            "2023",    # Missing month and day
          ]

          invalid_dates.each do |date|
            data = {"date" => JSON::Any.new(date)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{date} to be invalid"
          end
        end
      end

      describe "DateTime format" do
        it "passes for valid ISO8601 datetime strings" do
          validator = Format.new("datetime", Format::FormatType::DateTime)
          valid_datetimes = [
            "2023-12-25T10:30:00Z",
            "2023-12-25T10:30:00.123Z",
            "2023-12-25T10:30:00+00:00",
            "2023-12-25T10:30:00-05:00",
            "2023-12-25T10:30:00.123456Z",
          ]

          valid_datetimes.each do |datetime|
            data = {"datetime" => JSON::Any.new(datetime)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{datetime} to be valid"
          end
        end

        it "fails for invalid datetime strings" do
          validator = Format.new("datetime", Format::FormatType::DateTime)
          invalid_datetimes = [
            "2023-12-25",          # Date only
            "10:30:00",            # Time only
            "2023-12-25 10:30:00", # Space instead of T
            "not a datetime",
            "2023-12-25T25:00:00Z", # Invalid hour
            "2023-12-25T10:61:00Z", # Invalid minute
          ]

          invalid_datetimes.each do |datetime|
            data = {"datetime" => JSON::Any.new(datetime)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{datetime} to be invalid"
          end
        end
      end

      describe "Time format" do
        it "passes for valid time strings" do
          validator = Format.new("time", Format::FormatType::Time)
          valid_times = [
            "10:30:00",
            "00:00:00",
            "23:59:59",
            "12:34:56",
          ]

          valid_times.each do |time|
            data = {"time" => JSON::Any.new(time)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{time} to be valid"
          end
        end

        it "fails for invalid time strings" do
          validator = Format.new("time", Format::FormatType::Time)
          invalid_times = [
            "25:00:00",    # Invalid hour
            "10:61:00",    # Invalid minute
            "10:30:61",    # Invalid second
            "10:30",       # Missing seconds
            "10:30:00 AM", # With AM/PM
            "not a time",
          ]

          invalid_times.each do |time|
            data = {"time" => JSON::Any.new(time)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{time} to be invalid"
          end
        end
      end

      describe "IPv4 format" do
        it "passes for valid IPv4 addresses" do
          validator = Format.new("ip", Format::FormatType::IPv4)
          valid_ips = [
            "192.168.1.1",
            "10.0.0.0",
            "172.16.0.1",
            "8.8.8.8",
            "255.255.255.255",
            "0.0.0.0",
          ]

          valid_ips.each do |ip|
            data = {"ip" => JSON::Any.new(ip)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{ip} to be valid"
          end
        end

        it "fails for invalid IPv4 addresses" do
          validator = Format.new("ip", Format::FormatType::IPv4)
          invalid_ips = [
            "256.1.1.1",     # Out of range
            "192.168.1",     # Missing octet
            "192.168.1.1.1", # Extra octet
            "192.168.-1.1",  # Negative number
            "192.168.a.1",   # Letter
            "not an ip",
          ]

          invalid_ips.each do |ip|
            data = {"ip" => JSON::Any.new(ip)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{ip} to be invalid"
          end
        end
      end

      describe "IPv6 format" do
        it "passes for valid IPv6 addresses" do
          validator = Format.new("ip", Format::FormatType::IPv6)
          valid_ips = [
            "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
            "2001:db8:85a3::8a2e:370:7334",
            "::1",
            "::",
            "fe80::1",
            "::ffff:192.0.2.1", # IPv4-mapped IPv6
          ]

          valid_ips.each do |ip|
            data = {"ip" => JSON::Any.new(ip)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{ip} to be valid"
          end
        end

        it "fails for invalid IPv6 addresses" do
          validator = Format.new("ip", Format::FormatType::IPv6)
          invalid_ips = [
            "gggg::1",                         # Invalid hex
            "2001:0db8:85a3::8a2e:370g:7334",  # Invalid character
            "2001:0db8:85a3:::8a2e:0370:7334", # Too many colons
            "192.168.1.1",                     # IPv4
            "not an ip",
          ]

          invalid_ips.each do |ip|
            data = {"ip" => JSON::Any.new(ip)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{ip} to be invalid"
          end
        end
      end

      describe "Hostname format" do
        it "passes for valid hostnames" do
          validator = Format.new("hostname", Format::FormatType::Hostname)
          valid_hostnames = [
            "example.com",
            "subdomain.example.com",
            "test-server",
            "server123",
            "my-server-01.example.co.uk",
            "localhost",
            "a.b.c.d.e.f",
          ]

          valid_hostnames.each do |hostname|
            data = {"hostname" => JSON::Any.new(hostname)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{hostname} to be valid"
          end
        end

        it "fails for invalid hostnames" do
          validator = Format.new("hostname", Format::FormatType::Hostname)
          invalid_hostnames = [
            "-example.com",     # Leading hyphen
            "example.com-",     # Trailing hyphen
            "example..com",     # Double dot
            "example .com",     # Space
            "example@com",      # Invalid character
            "example.com:8080", # Port number
            ".example.com",     # Leading dot
            "example.com.",     # Trailing dot
          ]

          invalid_hostnames.each do |hostname|
            data = {"hostname" => JSON::Any.new(hostname)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{hostname} to be invalid"
          end
        end
      end

      describe "Phone format" do
        it "passes for valid E.164 phone numbers" do
          validator = Format.new("phone", Format::FormatType::Phone)
          valid_phones = [
            "+12345678901",
            "+442071234567",
            "+33123456789",
            "+861234567890",
            "12345678901", # Without + prefix
          ]

          valid_phones.each do |phone|
            data = {"phone" => JSON::Any.new(phone)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{phone} to be valid"
          end
        end

        it "fails for invalid phone numbers" do
          validator = Format.new("phone", Format::FormatType::Phone)
          invalid_phones = [
            "+0123456789",       # Leading zero after country code
            "123-456-7890",      # With formatting
            "(123) 456-7890",    # With formatting
            "+123",              # Too short
            "+1234567890123456", # Too long (>15 digits)
            "not a phone",
          ]

          invalid_phones.each do |phone|
            data = {"phone" => JSON::Any.new(phone)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{phone} to be invalid"
          end
        end
      end

      describe "Custom format" do
        it "validates using custom regex pattern" do
          pattern = /\A[A-Z]{2}\d{4}\z/ # Two uppercase letters followed by 4 digits
          validator = Format.new("code", Format::FormatType::Custom, pattern)

          # Valid codes
          ["AB1234", "XY9999", "ZZ0000"].each do |code|
            data = {"code" => JSON::Any.new(code)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_true, "Expected #{code} to be valid"
          end

          # Invalid codes
          ["ab1234", "AB123", "AB12345", "1234AB", "ABCDEF"].each do |code|
            data = {"code" => JSON::Any.new(code)}
            result = LegacyResult.new(true, data)
            schema = TestSchema.new(data)
            context = Context.new(data, result, schema)

            validator.validate(context)

            result.success.should be_false, "Expected #{code} to be invalid"
          end
        end

        it "raises error when custom format has no pattern" do
          expect_raises(ArgumentError, "Custom format requires a pattern") do
            Format.new("field", Format::FormatType::Custom)
          end
        end
      end

      describe "edge cases" do
        it "skips validation when field is missing" do
          validator = Format.new("email", Format::FormatType::Email)
          data = {} of String => JSON::Any
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation when field is nil" do
          validator = Format.new("email", Format::FormatType::Email)
          data = {"email" => JSON::Any.new(nil)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end

        it "skips validation for non-string values" do
          validator = Format.new("field", Format::FormatType::Email)
          data = {"field" => JSON::Any.new(123)}
          result = LegacyResult.new(true, data)
          schema = TestSchema.new(data)
          context = Context.new(data, result, schema)

          validator.validate(context)

          result.success.should be_true
        end
      end
    end
  end
end
