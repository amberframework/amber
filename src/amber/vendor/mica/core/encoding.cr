module Amber::Mica::Core
  # The character encodings Mica decodes in Crystal (no iconv).
  #
  # UTF-8 is read in place; the others go through `Core::Transcoder`, which
  # turns them into UTF-8 for the format's scanner.
  enum Encoding
    UTF8
    UTF16LE
    UTF16BE
    UTF32LE
    UTF32BE
    ISO8859_1
    USASCII

    # Returns the canonical name (`"UTF-8"`, `"UTF-16LE"`, ...).
    def label : String
      case self
      in .utf8?      then "UTF-8"
      in .utf16_le?  then "UTF-16LE"
      in .utf16_be?  then "UTF-16BE"
      in .utf32_le?  then "UTF-32LE"
      in .utf32_be?  then "UTF-32BE"
      in .iso8859_1? then "ISO-8859-1"
      in .usascii?   then "US-ASCII"
      end
    end

    # Returns true for the UTF-16 forms.
    def utf16? : Bool
      utf16_le? || utf16_be?
    end

    # Returns true for the UTF-32 forms.
    def utf32? : Bool
      utf32_le? || utf32_be?
    end

    # Returns true when the encoding must go through a `Transcoder`.
    def transcoded? : Bool
      utf16? || utf32? || iso8859_1?
    end

    # Returns the encoding a byte order mark announces at the start of
    # *bytes* and the mark's size, or nil. UTF-32LE wins over UTF-16LE when
    # the four bytes `FF FE 00 00` are present.
    #
    # ```
    # Amber::Mica::Core::Encoding.from_byte_order_mark(Bytes[0xFE, 0xFF, 0, 0x3C]) # => {Amber::Mica::Core::Encoding::UTF16BE, 2}
    # ```
    def self.from_byte_order_mark(bytes : Bytes) : {Encoding, Int32}?
      size = bytes.size
      return if size < 2
      b0, b1 = bytes[0], bytes[1]
      if size >= 4
        return {UTF32BE, 4} if b0 == 0 && b1 == 0 && bytes[2] == 0xFE && bytes[3] == 0xFF
        return {UTF32LE, 4} if b0 == 0xFF && b1 == 0xFE && bytes[2] == 0 && bytes[3] == 0
      end
      return {UTF8, 3} if size >= 3 && b0 == 0xEF && b1 == 0xBB && bytes[2] == 0xBF
      return {UTF16BE, 2} if b0 == 0xFE && b1 == 0xFF
      return {UTF16LE, 2} if b0 == 0xFF && b1 == 0xFE
      nil
    end

    # Looks up an encoding by name, ignoring ASCII case. Accepts the IANA
    # names and common aliases. `"UTF-16"` and `"UTF-32"` (no byte order)
    # map to the big-endian form, which is what they mean without a byte
    # order mark; formats that read a mark compare it separately.
    def self.from_label(name : String) : Encoding?
      case normalize_label(name)
      when "utf8"                     then UTF8
      when "utf16", "utf16be"         then UTF16BE
      when "utf16le"                  then UTF16LE
      when "utf32", "utf32be", "ucs4" then UTF32BE
      when "utf32le"                  then UTF32LE
      when "iso88591", "latin1", "l1", "iso885911987", "isoir100", "cp819", "ibm819", "csisolatin1"
        ISO8859_1
      when "usascii", "ascii", "iso646us", "ansix341968", "csascii", "us", "isoir6", "ibm367", "cp367"
        USASCII
      end
    end

    # Lowercases ASCII letters and drops `-`, `_`, `.`, `:` and spaces, so
    # `"ISO_8859-1"`, `"iso-8859-1"` and `"ISO8859_1"` compare equal.
    private def self.normalize_label(name : String) : String
      String.build(name.bytesize) do |io|
        name.each_byte do |byte|
          next if byte == '-'.ord || byte == '_'.ord || byte == '.'.ord || byte == ':'.ord || byte == ' '.ord
          io.write_byte(byte >= 'A'.ord && byte <= 'Z'.ord ? byte + 32 : byte)
        end
      end
    end
  end
end
