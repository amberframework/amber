module Amber::Beryl::Crypto::V1
  # How an ECDSA signature (r, s) is written down.
  enum SignatureFormat
    # The DER `ECDSA-Sig-Value` SEQUENCE of two INTEGERs (RFC 3279 §2.2.3,
    # RFC 5480), used by TLS and X.509.
    DER
    # r || s, each left-padded to the size of the group order (IEEE P1363),
    # used by COSE, JOSE and WebCrypto.
    FixedWidth
  end

  # :nodoc:
  #
  # Reads and writes the two signature formats. Reading is strict DER: short
  # length forms only (a P-384 signature is at most 104 bytes), INTEGERs
  # positive and minimal, nothing after the SEQUENCE. Inputs are public.
  module EllipticCurveSignatureEncoding
    TAG_SEQUENCE = 0x30_u8
    TAG_INTEGER  = 0x02_u8

    # Returns {r, s} as big-endian numbers of *bytesize* bytes, or nil when
    # *signature* is not a well-formed signature in *format*.
    def self.decode(signature : Bytes, format : SignatureFormat, bytesize : Int32) : {Bytes, Bytes}?
      if format.fixed_width?
        return nil unless signature.size == 2 * bytesize
        return {signature[0, bytesize].dup, signature[bytesize, bytesize].dup}
      end

      return nil unless signature.size >= 2 && signature[0] == TAG_SEQUENCE
      content_bytesize = signature[1].to_i32
      return nil if content_bytesize >= 0x80
      return nil unless signature.size == 2 + content_bytesize

      first = read_integer(signature, 2, bytesize)
      return nil unless first
      r, after_r = first
      second = read_integer(signature, after_r, bytesize)
      return nil unless second
      s, after_s = second
      return nil unless after_s == signature.size

      {r, s}
    end

    private def self.read_integer(signature : Bytes, offset : Int32, bytesize : Int32) : {Bytes, Int32}?
      return nil unless offset + 2 <= signature.size && signature[offset] == TAG_INTEGER
      length = signature[offset + 1].to_i32
      return nil if length == 0 || length >= 0x80
      start = offset + 2
      return nil unless start + length <= signature.size

      content = signature[start, length]
      return nil if content[0] & 0x80 != 0                                  # negative
      return nil if length > 1 && content[0] == 0 && content[1] & 0x80 == 0 # not minimal

      digits = content[0] == 0 && length > 1 ? content[1, length - 1] : content
      return nil if digits.size > bytesize

      value = Bytes.new(bytesize)
      digits.copy_to(value[bytesize - digits.size, digits.size])
      {value, start + length}
    end

    # Writes (r, s), each *bytesize* big-endian bytes, in *format*.
    def self.encode(r : Bytes, s : Bytes, format : SignatureFormat) : Bytes
      if format.fixed_width?
        encoded = Bytes.new(r.size + s.size)
        r.copy_to(encoded)
        s.copy_to(encoded[r.size, s.size])
        return encoded
      end

      encoded_r = encode_integer(r)
      encoded_s = encode_integer(s)
      encoded = Bytes.new(2 + encoded_r.size + encoded_s.size)
      encoded[0] = TAG_SEQUENCE
      encoded[1] = (encoded_r.size + encoded_s.size).to_u8
      encoded_r.copy_to(encoded[2, encoded_r.size])
      encoded_s.copy_to(encoded[2 + encoded_r.size, encoded_s.size])
      encoded
    end

    private def self.encode_integer(value : Bytes) : Bytes
      first_nonzero = value.index { |byte| byte != 0 } || value.size - 1
      digits = value[first_nonzero, value.size - first_nonzero]
      needs_zero = digits[0] & 0x80 != 0
      encoded = Bytes.new(2 + digits.size + (needs_zero ? 1 : 0))
      encoded[0] = TAG_INTEGER
      encoded[1] = (digits.size + (needs_zero ? 1 : 0)).to_u8
      digits.copy_to(encoded[needs_zero ? 3 : 2, digits.size])
      encoded
    end
  end
end
