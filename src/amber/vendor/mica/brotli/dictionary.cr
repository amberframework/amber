module Amber::Mica::Brotli
  # The RFC 7932 static dictionary (Appendix A): 122,784 bytes of words
  # from 4 to 24 bytes long, grouped by length.
  #
  # :nodoc:
  module Dictionary
    # The dictionary bytes, from google/brotli v1.2.1
    # `c/common/dictionary.bin` (sha256
    # 20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70,
    # checked by `spec/brotli/dictionary_spec.cr`).
    DATA = {{ read_file("#{__DIR__}/dictionary.bin") }}.to_slice

    # NDBITS (Appendix A): log2 of the number of words of each length.
    SIZE_BITS_BY_LENGTH = StaticArray[
      0_u8, 0_u8, 0_u8, 0_u8, 10_u8, 10_u8, 11_u8, 11_u8,
      10_u8, 10_u8, 10_u8, 10_u8, 10_u8, 9_u8, 9_u8, 8_u8,
      7_u8, 7_u8, 8_u8, 7_u8, 7_u8, 6_u8, 6_u8, 5_u8,
      5_u8,
    ]

    # DOFFSET (Appendix A): where the words of each length start.
    OFFSETS_BY_LENGTH = StaticArray[
      0, 0, 0, 0, 0, 4096, 9216, 21504,
      35840, 44032, 53248, 63488, 74752, 87040, 93696, 100864,
      104704, 106752, 108928, 113536, 115968, 118528, 119872, 121280,
      122016,
    ]

    # The shortest and longest words.
    MIN_WORD_LENGTH =  4
    MAX_WORD_LENGTH = 24
  end
end
