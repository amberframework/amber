require "base64"
require "./error"

module Amber::Beryl::Encoding
  # Reads PEM, the textual encoding of RFC 7468: blocks of base64 between
  # `-----BEGIN LABEL-----` and `-----END LABEL-----` lines.
  #
  # The reader takes the strict form of RFC 7468 §3 with the leniencies
  # its §5.2 allows: text outside the blocks is ignored (so a file can carry
  # comments or `openssl x509 -text` output), lines may end in LF or CRLF,
  # and base64 lines may be of any length. Inside a block only base64
  # characters and whitespace may appear, and the END label must match the
  # BEGIN label.
  #
  # ```
  # Amber::Beryl::Encoding::PEM.decode(File.read("chain.pem"), label: "CERTIFICATE") # => Array(Bytes)
  # ```
  module PrivacyEnhancedMail
    # One block: its label and the bytes it holds.
    record Block, label : String, bytes : Bytes

    # The largest PEM text the reader takes, 4 MiB (the Mozilla root set is
    # about 250 KB; a certificate chain a few KB).
    LARGEST_TEXT_BYTESIZE = 4 * 1024 * 1024

    # Returns every block in *text*, in order. Raises `MalformedEncoding`
    # for a block that is not well formed and `LimitExceeded` when the text
    # is larger than `LARGEST_TEXT_BYTESIZE`.
    def self.decode_blocks(text : String, *, largest_text_bytesize : Int32 = LARGEST_TEXT_BYTESIZE) : Array(Block)
      if text.bytesize > largest_text_bytesize
        raise LimitExceeded.new("the PEM text has #{text.bytesize} bytes; the limit is #{largest_text_bytesize}")
      end

      list_of_blocks = [] of Block
      open_label : String? = nil
      body = String::Builder.new
      text.each_line(chomp: true).with_index do |line, line_index|
        line = line.rstrip(" \t\r")
        if label = open_label
          if line.starts_with?("-----END ")
            end_label = encapsulation_label(line, "-----END ", line_index)
            unless end_label == label
              raise MalformedEncoding.new("the block opened as #{label} closes as #{end_label} (line #{line_index + 1})")
            end
            list_of_blocks << Block.new(label, decode_base64(body.to_s, line_index))
            open_label = nil
            body = String::Builder.new
          else
            body << line
          end
        elsif line.starts_with?("-----BEGIN ")
          open_label = encapsulation_label(line, "-----BEGIN ", line_index)
        end
      end
      raise MalformedEncoding.new("the block #{open_label} is never closed") if open_label
      list_of_blocks
    end

    # Returns the bytes of every block labeled *label* in *text*, ignoring
    # blocks with other labels.
    def self.decode(text : String, *, label : String) : Array(Bytes)
      decode_blocks(text).select { |block| block.label == label }.map(&.bytes)
    end

    # Returns *bytes* as one PEM block labeled *label*, with 64-character
    # lines (RFC 7468 §2).
    def self.encode(bytes : Bytes, *, label : String) : String
      String.build do |io|
        io << "-----BEGIN " << label << "-----\n"
        Base64.strict_encode(bytes).each_char.each_slice(64) do |list_of_characters|
          list_of_characters.each { |character| io << character }
          io << '\n'
        end
        io << "-----END " << label << "-----\n"
      end
    end

    private def self.encapsulation_label(line : String, prefix : String, line_index : Int32) : String
      unless line.ends_with?("-----") && line.size >= prefix.size + 5
        raise MalformedEncoding.new("a malformed encapsulation boundary (line #{line_index + 1})")
      end
      label = line[prefix.size, line.size - prefix.size - 5]
      # RFC 7468 §3: labels are printable ASCII other than '-', with single
      # spaces or hyphens between words.
      unless label.each_char.all? { |character| character.ascii_alphanumeric? || character == ' ' || character == '-' || character == '#' }
        raise MalformedEncoding.new("a label with characters RFC 7468 does not allow (line #{line_index + 1})")
      end
      label
    end

    private def self.decode_base64(body : String, line_index : Int32) : Bytes
      compact = body.delete(" \t")
      unless compact.each_char.all? { |character| character.ascii_alphanumeric? || character == '+' || character == '/' || character == '=' }
        raise MalformedEncoding.new("a block holds a character that is not base64 (before line #{line_index + 1})")
      end
      padding_index = compact.index('=')
      unless compact.size % 4 == 0 && (padding_index.nil? || padding_index >= compact.size - 2)
        raise MalformedEncoding.new("a block's base64 is not padded to whole groups (before line #{line_index + 1})")
      end
      decoded = Base64.decode(compact)
      # Base64 has one canonical encoding of any bytes; refuse the others
      # (padding bits set), so the bytes of a block decide its text.
      unless Base64.strict_encode(decoded) == compact
        raise MalformedEncoding.new("a block's base64 is not in its canonical form (before line #{line_index + 1})")
      end
      decoded
    end
  end

  alias PEM = PrivacyEnhancedMail
end
